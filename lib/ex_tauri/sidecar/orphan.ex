defmodule ExTauri.Sidecar.Orphan do
  @moduledoc """
  Recognising — and clearing out — packaged sidecars whose window is gone.

  The Tauri shell is the only thing that ever spawns a packaged sidecar, and
  Burrito's launcher `execve`s the BEAM in place rather than forking, so the
  shell is always the sidecar's direct parent. A sidecar reparented to init
  (PPID 1) has therefore definitively lost its window: nothing will heartbeat it
  again, nothing will SIGTERM it on quit, and it keeps every process its
  supervision tree owns running until the machine reboots.

  That is not hypothetical. It has now been observed in two ex_tauri apps on one
  machine: seven sidecars of one running at once, the oldest holding its HTTP
  port for three and a half days so that every later launch died on
  `:eaddrinuse`; and four of another, two days old, whose only remaining trace
  was the `ps` output — their unpack directories had already been replaced.

  Three parts to the answer:

    * `reclaim_port/2` takes the port back from an orphan before your endpoint
      tries to bind it, so a stale sidecar can no longer lock the user out;
    * `reap_orphans/1` stops the rest, which hold no port but go on running
      timers, pollers and child processes with no window to show them in;
    * `orphan?/0` lets a running sidecar notice that its *own* shell is gone,
      which is the case a heartbeat cannot see — a heartbeat that never arrived
      is indistinguishable from a slow boot, and
      `ExTauri.ShutdownManager` uses this as its fourth stop signal.

  ## Whose sidecar is it

  Burrito names the unpack directory after the *release*, and `mix
  ex_tauri.install` scaffolded that release as `:desktop` for everyone until it
  started deriving the name from the application. Every app installed before
  that shares one directory: two of them both unpack to
  `.burrito/desktop_erts-<vsn>_<app vsn>/`, and every predicate that answers on
  the path alone answers the same for both. That is not a hypothetical — it is
  how four sidecars of one app were read as abandoned instances of another, one
  blind sweep away from being SIGTERMed by a program that did not own them.

  A unique release name is the real fix and new installs get one, but this check
  has to hold regardless: the machine an app runs on is not the machine it was
  installed on, and the orphan it finds may well predate the rename.

  `identify/2` is what separates them: the release name cannot, but the payload
  can, because Burrito unpacks each application into `lib/<app>-<vsn>`. It has
  three answers rather than two, since the unpack directory of a *running*
  sidecar can be deleted out from under it — an upgrade that cleans up after
  itself leaves the old version running from a path that no longer exists, which
  is precisely the long-lived orphan this module exists for. "Cannot tell" has
  to stay distinguishable from "not ours", and the two callers weigh it
  differently:

    * `reclaim_port/2` evicts on `:unknown`. The port is yours by configuration,
      so a parentless Burrito sidecar squatting it is an old copy of you
      whichever way its directory went.
    * `reap_orphans/1` requires `:ours`. It sweeps the whole machine on nothing
      but a path shape, and leaking one of your own orphans is a far smaller
      harm than killing someone else's running app.

  ## Options

  Both entry points take:

    * `:otp_app` — the application Burrito unpacked, used to recognise your own
      payload. Defaults to the sanitised `:app_name`, which is already what most
      apps are called (`"Codrift"` -> `:codrift`).
    * `:release_name` — the release Burrito wrapped. Defaults to `"desktop"`,
      what `mix ex_tauri.install` generates.

  Unix only. On Windows every predicate answers "not an orphan", which degrades
  to doing nothing rather than guessing.
  """

  require Logger

  alias ExTauri.Paths

  @beam "beam.smp"

  # How long a SIGTERMed sidecar gets to release the port. It runs a real
  # application shutdown, so this is not instant.
  @term_grace 5_000
  @kill_grace 2_000
  @poll 200

  @typedoc "Outcome of trying to make the port bindable."
  @type reclaim :: :free | :reclaimed | {:blocked, String.t()}

  @typedoc """
  Whose release a sidecar is carrying.

  `:unknown` is a directory that was deleted while its process kept running, not
  a guess — see "Whose sidecar is it" above.
  """
  @type identity :: :ours | :foreign | :unknown

  @doc """
  Makes `port` bindable, evicting an abandoned sidecar if that is what holds it.

  Call it from `Application.start/2` before your endpoint's child spec, so the
  bind that follows cannot fail on a process nobody is coming back for:

      def start(_type, _args) do
        ExTauri.Sidecar.Orphan.ensure_port_available(4000)
        ...
      end

  Returns `:free` when nothing was in the way, `:reclaimed` when an orphan was
  stopped, and `{:blocked, reason}` when the holder is something that must not
  be killed — an instance that still has a window, another app, or a process
  that cannot be identified at all.
  """
  @spec reclaim_port(pos_integer(), keyword()) :: reclaim()
  def reclaim_port(port, opts \\ []) do
    if port_bindable?(port),
      do: :free,
      else: reclaim_from(listener_pid(port), port, opts)
  end

  @doc """
  `reclaim_port/2` plus `reap_orphans/1`, with the outcome logged.

  The convenience form, and the one to reach for at boot: freeing the port only
  deals with the one orphan that happened to win the race for it.
  """
  @spec ensure_port_available(pos_integer(), keyword()) :: :ok
  def ensure_port_available(port, opts \\ []) do
    case reclaim_port(port, opts) do
      :free ->
        :ok

      :reclaimed ->
        Logger.warning(
          "[ExTauri.Sidecar.Orphan] reclaimed port #{port} from an abandoned sidecar"
        )

      {:blocked, reason} ->
        # A failed bind reads as a generic supervisor error, and a packaged app's
        # log is the only trace it leaves, so name the real problem here.
        Logger.error(
          "[ExTauri.Sidecar.Orphan] port #{port} is already in use — #{reason}. " <>
            "This backend will fail to bind; quit the other instance and reopen this one."
        )
    end

    reap_orphans(opts)
    :ok
  rescue
    # Every probe below is best-effort. A boot must not fail because `lsof` is
    # missing or `ps` printed something unexpected.
    _ -> :ok
  end

  @doc """
  Stops every abandoned sidecar of *this* application, returning the pids it
  signalled.

  Freeing the port only deals with the one orphan that happened to win the race
  for it; the rest go on running with no window to show anything in. They can
  only be cleaned up from outside, so a starting sidecar does it on everyone's
  behalf.

  Only sidecars that prove they are yours: nothing swept here holds a port of
  yours or answers to you in any way, so a match on the path shape alone is the
  whole evidence, and it is evidence another ex_tauri app satisfies too.
  """
  @spec reap_orphans(keyword()) :: [pos_integer()]
  def reap_orphans(opts \\ []) do
    opts
    |> burrito_pids()
    |> Enum.filter(&(orphan_sidecar?(&1, opts) and identify(command(&1), opts) == :ours))
    |> Enum.map(fn pid ->
      Logger.warning(
        "[ExTauri.Sidecar.Orphan] stopping abandoned sidecar #{pid} (its window is gone)"
      )

      signal(pid, "TERM")
      pid
    end)
  end

  @doc """
  True when *this* process has lost the shell that spawned it.

  Only meaningful for a packaged sidecar, so the caller has to be one: a plain
  `mix ex_tauri.dev` backend is regularly a child of init and perfectly healthy.
  `ExTauri.ShutdownManager` gates it on `packaged?/0` for that reason.
  """
  @spec orphan?() :: boolean()
  def orphan? do
    unix?() and parent_pid(self_pid()) == 1
  end

  @doc """
  True when this process is a Burrito-wrapped sidecar rather than a dev server.

  Burrito's launcher sets `__BURRITO` in the environment it `execve`s with. It
  does *not* set `RELEASE_NAME`, which is the trap that makes desktop-only
  behaviour gated on `RELEASE_NAME` pass every local test and no-op in every
  shipped build.
  """
  @spec packaged?() :: boolean()
  def packaged? do
    System.get_env("__BURRITO") != nil or System.get_env("RELEASE_NAME") != nil
  end

  @doc "True when `pid` is a packaged sidecar — of any ex_tauri app — with no parent shell."
  @spec orphan_sidecar?(pos_integer(), keyword()) :: boolean()
  def orphan_sidecar?(pid, opts \\ []) do
    unix?() and pid != self_pid() and parent_pid(pid) == 1 and
      packaged_sidecar?(command(pid), opts)
  end

  @doc """
  True when `command` is the emulator of some packaged sidecar.

  Requiring `beam.smp` keeps the release's helper processes (`erl_child_setup`,
  `inet_gethost`) out of the match: they share the unpack path but are not the
  sidecar, and killing one tears the ports out from under a healthy instance.
  CLI invocations are excluded for the same reason from the other direction —
  see `cli_invocation?/1`.
  """
  @spec packaged_sidecar?(String.t() | nil, keyword()) :: boolean()
  def packaged_sidecar?(command, opts \\ [])
  def packaged_sidecar?(nil, _opts), do: false

  def packaged_sidecar?(command, opts) do
    String.contains?(command, marker(opts)) and String.contains?(command, @beam) and
      not cli_invocation?(command)
  end

  # Burrito appends a CLI subcommand's own arguments after `-extra`. Those
  # processes run out of the same unpack directory and carry the same payload,
  # so nothing above this line can tell them from a sidecar — and `myapp
  # some-command` run from a terminal, or spawned by an editor, is regularly a
  # child of init with no window it could have lost. The window's sidecar is
  # spawned with no arguments at all.
  defp cli_invocation?(command), do: Regex.match?(~r/-extra\s+\S/, command)

  @doc """
  Whether `command` is running your release, another app's, or one that can no
  longer be read.

  Answers from the unpack directory the process named in its own argv, so it
  costs a `File.ls/1` and no `ps`. A directory that is gone answers `:unknown`
  rather than `:foreign`: its payload was yours or it was not, and this cannot
  say which any more.
  """
  @spec identify(String.t() | nil, keyword()) :: identity()
  def identify(command, opts \\ [])
  def identify(nil, _opts), do: :unknown

  def identify(command, opts) do
    case Regex.run(unpack_root(opts), command) do
      [_, root] -> classify(File.ls(Path.join(root, "lib")), opts)
      nil -> :unknown
    end
  end

  defp classify({:ok, apps}, opts) do
    prefix = "#{otp_app(opts)}-"

    if Enum.any?(apps, &String.starts_with?(&1, prefix)), do: :ours, else: :foreign
  end

  defp classify({:error, _reason}, _opts), do: :unknown

  defp reclaim_from(nil, port, _opts),
    do: {:blocked, "could not identify the process listening on #{port}"}

  defp reclaim_from(pid, port, opts) do
    cond do
      not orphan_sidecar?(pid, opts) ->
        {:blocked, "pid #{pid} holds #{port} and is not an abandoned sidecar"}

      identify(command(pid), opts) == :foreign ->
        {:blocked, "pid #{pid} holds #{port} but carries another app's release"}

      true ->
        evict(pid, port)
    end
  end

  defp evict(pid, port) do
    Logger.warning(
      "[ExTauri.Sidecar.Orphan] port #{port} is held by abandoned sidecar #{pid} — stopping it"
    )

    signal(pid, "TERM")

    if wait_for_port(port, @term_grace) do
      :reclaimed
    else
      Logger.warning("[ExTauri.Sidecar.Orphan] sidecar #{pid} ignored SIGTERM — killing it")
      signal(pid, "KILL")

      if wait_for_port(port, @kill_grace),
        do: :reclaimed,
        else: {:blocked, "sidecar #{pid} was killed but #{port} is still not bindable"}
    end
  end

  defp wait_for_port(_port, remaining) when remaining <= 0, do: false

  defp wait_for_port(port, remaining) do
    Process.sleep(@poll)
    port_bindable?(port) or wait_for_port(port, remaining - @poll)
  end

  # Asks the question the endpoint is about to ask, rather than the weaker "does
  # anything answer a connection" — a socket stuck in a half-closed state
  # refuses connections while still owning the address.
  defp port_bindable?(port) do
    case :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, active: false, reuseaddr: true]) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _reason} ->
        false
    end
  end

  defp listener_pid(port) do
    with {out, 0} <- run("lsof", ["-nP", "-iTCP:#{port}", "-sTCP:LISTEN", "-t"]),
         [first | _] <- String.split(out, "\n", trim: true) do
      parse_pid(first)
    else
      _ -> nil
    end
  end

  defp burrito_pids(opts) do
    case run("pgrep", ["-f", marker(opts)]) do
      {out, 0} ->
        out |> String.split("\n", trim: true) |> Enum.map(&parse_pid/1) |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  # Burrito unpacks under Application Support on macOS and ~/.local/share on
  # Linux; both go through the same `.burrito/<release>_` directory.
  defp marker(opts), do: "/.burrito/#{release_name(opts)}_"

  # argv[0] is the emulator inside the unpack root, which is why this anchors and
  # matches lazily: `-root` repeats the same directory later on the command line
  # and a greedy match would read the last copy — on a machine with two ex_tauri
  # apps, that is how yours gets identified as theirs. The directory segment
  # itself never contains a space; the path above it does ("Application Support").
  defp unpack_root(opts) do
    ~r{^(.*?/\.burrito/#{Regex.escape(release_name(opts))}_[^/\s]+)/}
  end

  defp release_name(opts),
    do: opts[:release_name] || Application.get_env(:ex_tauri, :release_name, "desktop")

  # The sanitised app name is already the OTP application for most apps
  # ("Codrift" -> :codrift), which keeps this working with no extra configuration.
  defp otp_app(opts) do
    opts[:otp_app] || Application.get_env(:ex_tauri, :otp_app) ||
      Paths.sanitize_name(Application.get_env(:ex_tauri, :app_name, "ex_tauri_app"))
  end

  defp parent_pid(pid) do
    case run("ps", ["-o", "ppid=", "-p", Integer.to_string(pid)]) do
      {out, 0} -> parse_pid(out)
      _ -> nil
    end
  end

  defp command(pid) do
    case run("ps", ["-o", "command=", "-p", Integer.to_string(pid)]) do
      {out, 0} -> String.trim(out)
      _ -> nil
    end
  end

  defp signal(pid, name), do: run("kill", ["-#{name}", Integer.to_string(pid)])

  defp parse_pid(text) do
    case text |> String.trim() |> Integer.parse() do
      {pid, _rest} when pid > 0 -> pid
      _ -> nil
    end
  end

  defp self_pid, do: parse_pid(System.pid())

  defp unix?, do: match?({:unix, _}, :os.type())

  # Every caller here is best-effort: a missing `lsof` on a stripped Linux image
  # must degrade to "cannot tell", never crash the boot that is asking. stderr is
  # folded in rather than inherited so a probe for a pid that has already exited
  # cannot write to the app's log; a non-zero exit discards the output anyway.
  defp run(command, args) do
    System.cmd(command, args, stderr_to_stdout: true)
  rescue
    _ -> :error
  end
end
