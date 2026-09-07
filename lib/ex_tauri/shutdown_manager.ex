defmodule ExTauri.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the Phoenix application when running as a Tauri sidecar.

  This GenServer implements a heartbeat-based mechanism to detect when the Tauri
  frontend exits. The Rust frontend sends heartbeat signals every 100ms — over a
  Unix domain socket on macOS/Linux, or a localhost TCP socket on Windows — and
  if the Phoenix sidecar doesn't receive a heartbeat within 1500ms (configurable),
  it initiates graceful shutdown.

  ## Usage

  Add this to your application's supervision tree in `application.ex`:

      def start(_type, _args) do
        children = [
          ExTauri.ShutdownManager,
          # ... your other children
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## How it works

  The heartbeat mechanism provides robust shutdown detection:
  1. ShutdownManager opens a listener. On macOS/Linux this is a Unix domain
     socket at `<tmpdir>/tauri_heartbeat_<app_name>.sock`. On Windows (where the
     BEAM cannot listen on Unix domain sockets) it is a TCP socket bound to
     `127.0.0.1` on an ephemeral port, and the port number is written to
     `<tmpdir>/tauri_heartbeat_<app_name>.port` so the Rust frontend can find it
  2. Rust frontend connects and sends a byte every 100ms
  3. The acceptor reads bytes in the same process that accepted the connection and
     casts each one back as a heartbeat (reading from another process would fail)
  4. Every 500ms, ShutdownManager checks if a heartbeat was received recently
  5. Once the frontend has connected at least once, no heartbeat for 1500ms
     initiates graceful shutdown; before the first connection the timeout is not
     enforced, so a slow boot can't shut the app down before the window attaches

  The socket path is unique per application (based on `:app_name` config) to prevent
  collisions when multiple ExTauri applications run simultaneously.

  This works even when:
  - The app is force-quit (CMD+Q on macOS)
  - The app crashes unexpectedly
  - The process is killed without cleanup

  ## The four stop signals

  A heartbeat that stops is not the only way a window goes away, and each of the
  three additions below closes a case that left real sidecars running for days.

  1. **The connection closing.** The kernel closes a dead process's sockets, so
     this is the unambiguous "window gone" signal and the one a crash or a
     force-quit actually trips. The frontend reconnects on drop, so it only
     counts after `:heartbeat_reconnect_grace` has passed with nothing
     reconnecting.
  2. **Bytes stopping** for `:heartbeat_timeout` while the connection stays
     open — the backstop for a shell that is alive but wedged.
  3. **A heartbeat that never started, on a process reparented to init.** The
     startup grace deliberately makes "no heartbeat yet" immortal, because a
     slow boot must not kill itself — so a shell that died before it could
     connect, or whose socket a second sidecar unlinked, left its backend
     running until the machine rebooted. `ExTauri.Sidecar.Orphan.orphan?/0`
     answers it from the other end: the shell is the only thing that spawns a
     packaged sidecar, so a PPID of 1 proves the window is gone whatever the
     socket says. It shells out to `ps`, so it runs only after
     `:heartbeat_orphan_grace` and is throttled after that, and only in a
     packaged build — a `mix ex_tauri.dev` backend is regularly a child of init
     and perfectly healthy.
  4. **A check that runs late rebaselines instead of shutting down.** When the
     machine sleeps both sides freeze, they do not resume together, and the
     monotonic clock keeps running across the sleep — so the first check after a
     wake measures a gap that says nothing about whether the window is alive.
     That is how an ordinary lid-close killed a backend: "heartbeat timeout
     (1610ms)" moments after the wake, with the shell still on screen. A check
     more than `:heartbeat_stall_grace` later than it was scheduled proves *this*
     process was not running either, which makes every elapsed measurement
     across it meaningless.

  `:heartbeat_timeout` stays at 1500ms because the Windows frontend has no
  SIGTERM to send and quits by letting this time out — raising the default would
  make every Windows quit that much slower. On macOS and Linux the closed
  connection does the real work, so an app that sees false positives on a loaded
  machine can raise the timeout without losing anything.

  ## Configuration

  Heartbeat timing can be configured in your `config/config.exs`:

      config :ex_tauri,
        heartbeat_interval: 500,  # How often to check heartbeat (ms, default: 500)
        heartbeat_timeout: 1500   # Time without heartbeat before shutdown (ms, default: 1500)

  The transport is selected automatically from the OS (`:unix` on macOS/Linux,
  `:tcp` on Windows). It can be forced with the `:heartbeat_transport` config
  key or the `:transport` start option, which is mainly useful for tests.

  ## The desktop channel

  Beyond liveness, the socket carries a newline-delimited JSON protocol in both
  directions: the Rust frontend sends heartbeats and native events (menu and
  tray clicks), and Elixir sends desktop commands (notifications, tray setup).
  Use `ExTauri.Desktop` rather than talking to this server directly.
  """

  use GenServer
  require Logger

  @default_heartbeat_interval 500
  @default_heartbeat_timeout 1500
  # A check running this much later than scheduled means the VM was frozen
  # (system sleep, SIGSTOP), not that the frontend stopped writing.
  @default_stall_grace 1000
  # How long the socket may stay closed before the window counts as gone. The
  # Rust frontend retries every 100ms, so this only has to outlast a reconnect.
  @default_reconnect_grace 3000
  # How long a sidecar may go without ever being heartbeated before the orphan
  # check starts asking whether it still has a shell. Comfortably past the Rust
  # side's own wait for the server port, so a slow first launch is never suspected.
  @default_orphan_grace 60_000
  # The check forks `ps`, so it is throttled well below the heartbeat interval.
  @orphan_check_interval 5000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Trap exits so we can perform graceful shutdown
    Process.flag(:trap_exit, true)

    # Options take precedence over application config, which falls back to the
    # built-in defaults. Passing opts (used in tests) keeps configuration
    # explicit and avoids mutating global application env.
    heartbeat_interval =
      opts[:heartbeat_interval] ||
        Application.get_env(:ex_tauri, :heartbeat_interval, @default_heartbeat_interval)

    heartbeat_timeout =
      opts[:heartbeat_timeout] ||
        Application.get_env(:ex_tauri, :heartbeat_timeout, @default_heartbeat_timeout)

    # The action taken once the heartbeat is lost. Defaults to stopping the BEAM;
    # tests inject a benign function so the suite isn't torn down by System.stop/1.
    shutdown_fun = opts[:shutdown_fun] || (&default_shutdown/0)

    # Create socket path using app name to prevent collisions
    app_name = opts[:app_name] || Application.get_env(:ex_tauri, :app_name, "ex_tauri_app")
    socket_name = ExTauri.Paths.sanitize_name(app_name)

    # Unix domain sockets on macOS/Linux; localhost TCP + a port discovery file
    # on Windows, where the BEAM cannot listen on Unix domain sockets.
    transport =
      opts[:transport] ||
        Application.get_env(:ex_tauri, :heartbeat_transport, default_transport())

    stall_grace = setting(opts, :heartbeat_stall_grace, @default_stall_grace)
    reconnect_grace = setting(opts, :heartbeat_reconnect_grace, @default_reconnect_grace)
    orphan_grace = setting(opts, :heartbeat_orphan_grace, @default_orphan_grace)

    # Injectable so the suite can exercise the orphan path without reparenting a
    # real OS process. In production it only ever runs in a packaged build.
    orphan_check =
      opts[:orphan_check] ||
        fn -> ExTauri.Sidecar.Orphan.packaged?() and ExTauri.Sidecar.Orphan.orphan?() end

    {listen_socket, endpoint, cleanup_paths} = open_listener(transport, socket_name)

    # Spawn acceptor process under the ExTauri TaskSupervisor
    if listen_socket do
      Task.Supervisor.start_child(ExTauri.TaskSupervisor, fn -> accept_loop(listen_socket) end)
    end

    Logger.info("[ExTauri.ShutdownManager] Started - heartbeat monitoring active on #{endpoint}")

    {:ok,
     %{
       listen_socket: listen_socket,
       cleanup_paths: cleanup_paths,
       started_at: System.monotonic_time(:millisecond),
       last_heartbeat: System.monotonic_time(:millisecond),
       # Schedule the first heartbeat check, remembering when it is due — that is
       # what makes a late one (a frozen VM) detectable when it finally runs.
       next_check: schedule_heartbeat_check(heartbeat_interval),
       # Stays false until the frontend connects at least once. While false a
       # heartbeat timeout means "still booting", not "window gone".
       connected: false,
       # When the frontend's connection dropped, if it is currently down.
       disconnected_at: nil,
       # When the orphan check last forked `ps`, so it can be throttled.
       last_orphan_check: nil,
       shutdown_initiated: false,
       heartbeat_interval: heartbeat_interval,
       heartbeat_timeout: heartbeat_timeout,
       stall_grace: stall_grace,
       reconnect_grace: reconnect_grace,
       orphan_grace: orphan_grace,
       orphan_check: orphan_check,
       shutdown_fun: shutdown_fun,
       # Duplex channel state: the currently connected frontend socket (for
       # outbound ExTauri.Desktop commands) and processes subscribed to
       # native events (pid => monitor ref).
       client_socket: nil,
       subscribers: %{}
     }}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    # Record the heartbeat and mark the frontend as having connected at least once.
    # Any traffic also cancels a pending disconnect: the frontend reconnected.
    {:noreply,
     %{
       state
       | last_heartbeat: System.monotonic_time(:millisecond),
         connected: true,
         disconnected_at: nil
     }}
  end

  def handle_cast({:client_connected, socket}, state) do
    {:noreply, %{state | client_socket: socket, disconnected_at: nil}}
  end

  def handle_cast({:client_disconnected, socket}, state) do
    if state.client_socket == socket do
      # The kernel closes a dead process's sockets, so this is the signal a
      # crash or a force-quit actually trips. Before the first heartbeat it says
      # nothing — anything can open the socket — so it only starts the clock
      # once the frontend has spoken.
      {:noreply, %{state | client_socket: nil, disconnected_at: disconnect_time(state)}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:channel_event, name, payload}, state) do
    for {pid, _ref} <- state.subscribers do
      send(pid, {:ex_tauri_event, name, payload})
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:desktop_command, name, payload}, _from, state) do
    case state.client_socket do
      nil ->
        {:reply, {:error, :not_connected}, state}

      socket ->
        line = Jason.encode!(%{type: "command", name: name, payload: payload}) <> "\n"

        case :gen_tcp.send(socket, line) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, %{state | client_socket: nil}}
        end
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    if Map.has_key?(state.subscribers, pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(pid)
      {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        {:reply, :ok, state}

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  @impl true
  def handle_info(:check_heartbeat, %{connected: false} = state) do
    # Startup grace: the timeout only applies once the frontend has connected at
    # least once. The frontend connects only after the server port is up, so
    # before the first heartbeat "no heartbeat yet" is the still-booting case, not
    # a lost window. Enforcing the timeout here would shut the app down mid-boot.
    #
    # Which leaves this state immortal, and that is the one a sidecar whose shell
    # died before it could connect gets stuck in. Losing the parent shell is the
    # one thing no slow boot can do, so it is the only proof accepted here.
    now = System.monotonic_time(:millisecond)

    cond do
      not orphan_check_due?(state, now) ->
        {:noreply, rearm(state)}

      state.orphan_check.() ->
        Logger.warning(
          "[ExTauri.ShutdownManager] No heartbeat has ever arrived and this process has been " <>
            "reparented to init - the window that spawned it is gone, stopping"
        )

        initiate_shutdown(state)

      true ->
        {:noreply, rearm(%{state | last_orphan_check: now})}
    end
  end

  def handle_info(:check_heartbeat, state) do
    now = System.monotonic_time(:millisecond)
    late = now - state.next_check
    elapsed = now - state.last_heartbeat

    cond do
      late > state.stall_grace ->
        # The VM was frozen (system sleep, SIGSTOP), so every elapsed measurement
        # across it is meaningless. Rebaseline and give the window another
        # interval rather than reading the freeze as a dead frontend.
        Logger.info(
          "[ExTauri.ShutdownManager] Check ran #{late}ms late - process was frozen, " <>
            "resetting the heartbeat baseline"
        )

        {:noreply,
         rearm(%{state | last_heartbeat: now, disconnected_at: state.disconnected_at && now})}

      state.disconnected_at && now - state.disconnected_at > state.reconnect_grace ->
        Logger.warning(
          "[ExTauri.ShutdownManager] Heartbeat socket closed and no reconnect in " <>
            "#{now - state.disconnected_at}ms - Tauri frontend is gone"
        )

        initiate_shutdown(state)

      elapsed > state.heartbeat_timeout ->
        Logger.warning(
          "[ExTauri.ShutdownManager] Heartbeat timeout (#{elapsed}ms) - Tauri frontend appears to have exited"
        )

        initiate_shutdown(state)

      true ->
        # Still receiving heartbeats, schedule next check
        {:noreply, rearm(state)}
    end
  end

  @impl true
  def handle_info(:execute_shutdown, state) do
    Logger.info("[ExTauri.ShutdownManager] Stopping application...")
    state.shutdown_fun.()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  def handle_info(msg, state) do
    Logger.debug("[ExTauri.ShutdownManager] Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[ExTauri.ShutdownManager] Terminating: #{inspect(reason)}")
    if state.listen_socket, do: :gen_tcp.close(state.listen_socket)
    Enum.each(state.cleanup_paths, &File.rm/1)
    :ok
  end

  defp setting(opts, key, default),
    do: opts[key] || Application.get_env(:ex_tauri, key, default)

  defp rearm(state),
    do: %{state | next_check: schedule_heartbeat_check(state.heartbeat_interval)}

  # A disconnect before the first heartbeat is not evidence of anything: any
  # process can open the socket and close it again.
  defp disconnect_time(%{connected: true, disconnected_at: nil}),
    do: System.monotonic_time(:millisecond)

  defp disconnect_time(state), do: state.disconnected_at

  # Only after the grace has passed with nothing heard, and only every
  # @orphan_check_interval after that - the check forks `ps`, while the heartbeat
  # interval is half a second.
  defp orphan_check_due?(state, now) do
    now - state.started_at > state.orphan_grace and
      (is_nil(state.last_orphan_check) or now - state.last_orphan_check >= @orphan_check_interval)
  end

  defp default_shutdown do
    System.stop(0)
  end

  defp default_transport do
    case :os.type() do
      {:win32, _} -> :tcp
      _ -> :unix
    end
  end

  defp open_listener(:unix, socket_name) do
    socket_path = Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.sock")

    remove_stale_socket(socket_path)

    opts = [:binary, {:ifaddr, {:local, socket_path}}, {:active, false}, {:reuseaddr, true}]

    case :gen_tcp.listen(0, opts) do
      {:ok, listen_socket} ->
        # Restrict socket to owner-only access (prevents local privilege escalation)
        File.chmod(socket_path, 0o600)
        {listen_socket, socket_path, [socket_path]}

      {:error, reason} ->
        # An unmatched `{:ok, socket} =` here turned "another instance owns this
        # socket path" into a crash that took the whole supervision tree with it,
        # restart after restart. Degrading to a manager with no listener keeps the
        # orphan check - the one signal that does not need the socket - alive to
        # stop this process properly. Nothing is cleaned up on terminate either:
        # the file belongs to whoever is listening on it, and that is not us.
        Logger.error(
          "[ExTauri.ShutdownManager] Could not listen on #{socket_path} " <>
            "(#{inspect(reason)}) - no heartbeat will be received; " <>
            "falling back to the orphan check"
        )

        {nil, socket_path, []}
    end
  end

  defp open_listener(:tcp, socket_name) do
    port_file = Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.port")

    # Clean up a stale port file so the frontend can't connect to a dead port
    File.rm(port_file)

    # Bind to loopback only; port 0 lets the OS pick a free ephemeral port,
    # which is then published through the port file for the Rust frontend.
    opts = [:binary, {:ip, {127, 0, 0, 1}}, {:active, false}, {:reuseaddr, true}]

    case :gen_tcp.listen(0, opts) do
      {:ok, listen_socket} ->
        {:ok, port} = :inet.port(listen_socket)
        File.write!(port_file, Integer.to_string(port))
        File.chmod(port_file, 0o600)

        {listen_socket, "127.0.0.1:#{port}", [port_file]}

      {:error, reason} ->
        # Same reasoning as the Unix branch: never crash the tree over a socket.
        Logger.error(
          "[ExTauri.ShutdownManager] Could not listen on 127.0.0.1 (#{inspect(reason)}) - " <>
            "no heartbeat will be received; falling back to the orphan check"
        )

        {nil, "127.0.0.1 (unavailable)", []}
    end
  end

  # Only unlink a socket nobody is listening on. The unconditional `File.rm` this
  # replaces meant a second sidecar booting - or dying seconds later and running
  # `terminate` - deleted the *live* instance's socket file. That listener
  # survives but becomes unreachable, so its window can never reconnect; and
  # since a heartbeat that never arrived is the state the startup grace makes
  # immortal, the backend then runs until the machine reboots. Connecting is the
  # only way to tell a stale path from a live one.
  defp remove_stale_socket(socket_path) do
    if File.exists?(socket_path) do
      case :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false], 200) do
        {:ok, socket} ->
          :gen_tcp.close(socket)

          Logger.warning(
            "[ExTauri.ShutdownManager] Another instance is listening on #{socket_path} - " <>
              "leaving it in place"
          )

        {:error, _reason} ->
          File.rm(socket_path)
      end
    end

    :ok
  end

  # Returns the moment the check is due, which is what makes a late one - a
  # frozen VM - detectable when it finally runs.
  defp schedule_heartbeat_check(interval) do
    Process.send_after(self(), :check_heartbeat, interval)
    System.monotonic_time(:millisecond) + interval
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket, 1000) do
      {:ok, client_socket} ->
        # Read in THIS process — the one that accepted. recv on a passive socket
        # from a separately-spawned process returns {:error, :closed}, so reading
        # the heartbeat elsewhere silently drops every byte and the frontend never
        # registers as connected. The frontend holds one connection at a time
        # (reconnecting on drop), so handling them sequentially is enough.
        #
        # The manager keeps the socket for outbound ExTauri.Desktop commands
        # (gen_tcp.send is allowed from other processes; only recv is
        # restricted to this one).
        GenServer.cast(__MODULE__, {:client_connected, client_socket})
        recv_loop(client_socket)
        GenServer.cast(__MODULE__, {:client_disconnected, client_socket})
        accept_loop(listen_socket)

      {:error, :timeout} ->
        # Normal timeout, just continue
        accept_loop(listen_socket)

      {:error, :closed} ->
        Logger.info("[ExTauri.ShutdownManager] Listen socket closed, stopping accept loop")

      {:error, reason} ->
        Logger.error("[ExTauri.ShutdownManager] Accept error: #{inspect(reason)}")
    end
  end

  defp recv_loop(client_socket, buffer \\ "") do
    case :gen_tcp.recv(client_socket, 0) do
      {:ok, data} ->
        # Any traffic counts as liveness, whatever its content.
        GenServer.cast(__MODULE__, :heartbeat)
        buffer = process_channel_data(buffer <> data)
        recv_loop(client_socket, buffer)

      {:error, reason} ->
        unless reason == :closed do
          Logger.debug("[ExTauri.ShutdownManager] Client recv error: #{inspect(reason)}")
        end

        :gen_tcp.close(client_socket)
    end
  end

  # The channel protocol is newline-delimited JSON. Complete lines are
  # dispatched; the trailing partial line is returned as the new buffer.
  defp process_channel_data(buffer) do
    case String.split(buffer, "\n") do
      [incomplete] ->
        # Legacy frontends send bare heartbeat bytes with no newlines — don't
        # let them accumulate. Anything protocol-shaped is far smaller.
        if byte_size(incomplete) > 4096, do: "", else: incomplete

      parts ->
        {lines, [rest]} = Enum.split(parts, -1)
        Enum.each(lines, &dispatch_channel_line/1)
        rest
    end
  end

  defp dispatch_channel_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "heartbeat"}} ->
        :ok

      {:ok, %{"type" => "event", "name" => name} = message} ->
        GenServer.cast(__MODULE__, {:channel_event, name, message["payload"]})

      _other ->
        # Unknown or legacy content — already counted as a heartbeat.
        :ok
    end
  end

  defp initiate_shutdown(%{shutdown_initiated: true} = state) do
    # Shutdown already in progress, ignore
    {:noreply, state}
  end

  defp initiate_shutdown(state) do
    Logger.info("[ExTauri.ShutdownManager] Starting graceful shutdown sequence...")

    # Perform any cleanup here if needed
    # For example, you could broadcast a shutdown event to LiveView clients
    # Phoenix.PubSub.broadcast(MyApp.PubSub, "system", {:shutdown, :graceful})

    # Schedule shutdown to give the system a moment to clean up
    # Without blocking the GenServer
    Process.send_after(self(), :execute_shutdown, 100)

    {:noreply, %{state | shutdown_initiated: true}}
  end
end
