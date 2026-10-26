defmodule Mix.Tasks.ExTauri.Ios do
  @moduledoc """
  Builds the app for iPhone and iPad and runs it in the iOS simulator.

  ## Usage

      $ mix ex_tauri.ios init          # once: prepare src-tauri for iOS
      $ mix ex_tauri.ios run           # pack the backend, build, run in the simulator
      $ mix ex_tauri.ios dev           # the simulator on your dev server, live reload
      $ mix ex_tauri.ios build         # build only

  ## Options

    * `--device NAME|UDID` — the simulator to run on (`run`, `dev`). Defaults
      to one already booted, else the first iPad. `xcrun simctl list devices`
      shows them; pass an iPhone's name to try the phone layout.
    * `--console` — stay attached and print the app's output (`run`, `dev`).
    * `--force` — `init` replaces a `src-tauri/src/lib.rs` it did not write,
      and regenerates the Xcode project.
    * `--allow-older-runtime` — build even when the newest installed simulator
      runtime is older than Xcode's simulator SDK. `cargo tauri ios build`
      refuses that pairing although the app runs fine on the older runtime;
      this reports the installed runtime as the SDK's version to that one check.

  ## How the app runs

  A Tauri app cannot ship a sidecar on iOS, so `init` writes an iOS shell to
  `src-tauri/src/lib.rs` that starts the backend itself. `run` packs the
  release with ampoule (see `ExTauri.Packager`) for this Mac's architecture —
  the simulator runs Mac binaries — and bundles it into the app, which starts it
  as a child process bound to loopback and points its window at it. The desktop
  build is untouched: it still starts in `main.rs`, with whichever packager is
  configured.

  This runs in the simulator only. A device forbids both starting a process and
  the executable memory ampoule's engine maps; the shell says so if installed on
  one.

  `dev` builds the shell without a backend and launches it pointed at the dev
  server from `config :ex_tauri, :dev_command` on `:host`/`:port`, which it then
  runs in the foreground: the simulator shares the Mac's loopback, so live
  reload works as in a browser.

  ## Requirements

  Xcode with an iOS simulator runtime, the Rust iOS targets
  (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim`), and for `run`
  ampoule and OTP 28 (see `ExTauri.Packager`).
  """

  @shortdoc "Builds and runs the app in the iOS simulator"

  use Mix.Task

  alias ExTauri.Ios

  @switches [force: :boolean, device: :string, console: :boolean, allow_older_runtime: :boolean]

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: @switches)
    ExTauri.TaskHelpers.preflight_check!(otp: false)

    case rest do
      ["init"] -> init(opts)
      ["build"] -> build(opts, backend: true)
      ["run"] -> opts |> build(backend: true) |> launch(opts, [])
      ["dev"] -> dev(opts)
      _ -> Mix.raise("Usage: mix ex_tauri.ios init|build|run|dev [options]")
    end
  end

  defp init(opts) do
    write_lib_rs(opts)

    update_file("src-tauri/Cargo.toml", &Ios.mobile_cargo_toml/1)

    base = base_conf()
    write_json("src-tauri/tauri.ios.conf.json", Ios.ios_conf(base))
    File.mkdir_p!("src-tauri/mobile")
    File.write!("src-tauri/mobile/index.html", Ios.loading_page(base["productName"] || "the app"))

    if opts[:force] || not File.dir?("src-tauri/gen/apple") do
      ExTauri.run_simple(["ios", "init", "--ci"])
    end

    Mix.shell().info("""

    iOS ready. Run it in the simulator with:

        mix ex_tauri.ios run       # the packed backend, as it would ship
        mix ex_tauri.ios dev       # your dev server, live reload
    """)
  end

  defp write_lib_rs(opts) do
    path = "src-tauri/src/lib.rs"
    existing = if File.exists?(path), do: File.read!(path)

    action = if opts[:force], do: :write, else: Ios.lib_rs_action(existing)

    case action do
      :write ->
        host = Application.get_env(:ex_tauri, :host, "localhost")
        scheme = Application.get_env(:ex_tauri, :scheme, "http")
        File.write!(path, ExTauri.Install.Helpers.mobile_src(host, scheme))
        Mix.shell().info("* wrote #{path}")

      {:refuse, reason} ->
        Mix.raise(reason)
    end
  end

  # Returns what launching needs: the built app and its bundle identifier.
  defp build(opts, backend: backend?) do
    unless File.read!("src-tauri/src/lib.rs" |> ensure_exists()) =~ "ex_tauri:mobile-shell" do
      Mix.raise("src-tauri is not prepared for iOS yet. Run: mix ex_tauri.ios init")
    end

    host = ExTauri.host_triplet()

    target =
      case Ios.simulator_target(host) do
        {:ok, target} -> target
        {:error, message} -> Mix.raise(message)
      end

    if backend? do
      ExTauri.TaskHelpers.check_otp_version(:ampoule)
      ExTauri.Packager.package(host, packager: :ampoule, dest: Ios.backend_path())
    else
      # `dev` runs no backend, but the bundle still lists one as a resource.
      unless File.exists?(Ios.backend_path()) do
        File.mkdir_p!(Path.dirname(Ios.backend_path()))
        File.write!(Ios.backend_path(), "")
      end
    end

    # Xcode's build phase runs `cargo tauri ios xcode-script`, so the CLI ex_tauri
    # installed has to be on PATH as a cargo subcommand.
    path =
      shim_dirs(opts) ++
        [Path.join(ExTauri.installation_path(), "bin"), System.get_env("PATH", "")]

    ExTauri.run_simple(["ios", "build", "--target", target, "--debug", "--ci"], [
      {"PATH", Enum.join(path, ":")}
    ])

    base = base_conf()
    ios = read_json("src-tauri/tauri.ios.conf.json")
    name = base["productName"] || Mix.raise("tauri.conf.json has no productName")
    app = Path.join(["src-tauri/gen/apple/build", Ios.app_dir(target), name <> ".app"])

    File.dir?(app) || Mix.raise("the build reported success but #{app} is missing")
    Mix.shell().info("Built #{app}")

    %{app: app, bundle_id: Ios.bundle_id(base, ios)}
  end

  defp dev(opts) do
    built = build(opts, backend: false)

    host = Application.get_env(:ex_tauri, :host, "localhost")
    port = Application.get_env(:ex_tauri, :port, 4000)
    scheme = Application.get_env(:ex_tauri, :scheme, "http")
    url = "#{scheme}://#{host}:#{port}"

    # Launched first: the shell waits for the URL, and the dev server below
    # holds the terminal until it is stopped.
    launch(built, Keyword.put(opts, :console, false), [{"EX_TAURI_DEV_URL", url}])

    command = ExTauri.Sidecar.DevServer.command()
    Mix.shell().info("Starting `#{command}` for the simulator at #{url} (Ctrl-C to stop)")

    System.cmd("sh", ["-c", command],
      env: [{"PORT", to_string(port)}],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    )
  end

  defp launch(%{app: app, bundle_id: bundle_id}, opts, app_env) do
    device =
      case Ios.pick_device(simctl_json(["list", "devices", "available"]), opts[:device]) do
        {:ok, device} -> device
        {:error, message} -> Mix.raise(message)
      end

    udid = device["udid"]
    Mix.shell().info("Running on #{device["name"]} (#{udid})")

    if device["state"] != "Booted", do: xcrun!(["simctl", "boot", udid])
    open_simulator_window(udid)

    xcrun!(["simctl", "install", udid, app])
    System.cmd("xcrun", ["simctl", "terminate", udid, bundle_id], stderr_to_stdout: true)

    # simctl hands SIMCTL_CHILD_-prefixed variables to the app it launches.
    env = for {key, value} <- app_env, do: {"SIMCTL_CHILD_" <> key, value}
    console = if opts[:console], do: ["--console-pty"], else: []

    {_, status} =
      System.cmd("xcrun", ["simctl", "launch"] ++ console ++ [udid, bundle_id],
        env: env,
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    status == 0 || Mix.raise("the app did not launch (xcrun simctl launch exited #{status})")
  end

  # Xcode 27 has no Simulator.app; its simulator window is DeviceHub.
  defp open_simulator_window(udid) do
    {developer, 0} = System.cmd("xcode-select", ["-p"])

    candidates = [
      Path.join(String.trim(developer), "Applications/Simulator.app"),
      Path.join(String.trim(developer), "../Applications/DeviceHub.app") |> Path.expand()
    ]

    case Enum.find(candidates, &File.dir?/1) do
      nil ->
        Mix.shell().info("No simulator window app found; the app still runs headless.")

      app ->
        System.cmd("open", ["-a", app, "--args", "-CurrentDeviceUDID", udid])
    end
  end

  # The xcrun shim's directory when the runtime is older than the SDK and that
  # was allowed; otherwise a clear refusal instead of cargo-mobile2's.
  defp shim_dirs(opts) do
    {sdk, 0} = System.cmd("xcrun", ["--sdk", "iphonesimulator", "--show-sdk-version"])
    sdk = String.trim(sdk)
    runtimes = simctl_json(["list", "runtimes"])

    cond do
      Ios.runtime_covers_sdk?(runtimes, sdk) ->
        []

      opts[:allow_older_runtime] && Ios.newest_runtime(runtimes) ->
        dir = Path.join(Mix.Project.build_path(), "ex_tauri_ios")
        File.mkdir_p!(dir)
        shim = Path.join(dir, "xcrun")
        File.write!(shim, Ios.xcrun_shim(Ios.newest_runtime(runtimes), sdk))
        File.chmod!(shim, 0o755)
        [dir]

      true ->
        Mix.raise("""
        Xcode's iOS simulator SDK is #{sdk}, but the newest installed simulator
        runtime is #{Ios.newest_runtime(runtimes) || "none"}, and `cargo tauri ios build`
        refuses to build for that pairing.

        Either install the matching runtime (several GB):

            xcodebuild -downloadPlatform iOS

        or build anyway — the app runs on the older runtime:

            mix ex_tauri.ios run --allow-older-runtime
        """)
    end
  end

  defp simctl_json(args) do
    {json, 0} = System.cmd("xcrun", ["simctl" | args] ++ ["--json"])
    Jason.decode!(json)
  end

  defp xcrun!(args) do
    case System.cmd("xcrun", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, status} -> Mix.raise("xcrun #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  defp base_conf, do: read_json("src-tauri/tauri.conf.json")

  defp read_json(path), do: path |> File.read!() |> Jason.decode!()

  defp write_json(path, map) do
    File.write!(path, Jason.encode!(map, pretty: true) <> "\n")
    Mix.shell().info("* wrote #{path}")
  end

  defp update_file(path, fun) do
    content = File.read!(path)
    updated = fun.(content)

    if updated != content do
      File.write!(path, updated)
      Mix.shell().info("* updated #{path}")
    end
  end

  defp ensure_exists(path) do
    File.exists?(path) ||
      Mix.raise("src-tauri is not prepared for iOS yet. Run: mix ex_tauri.ios init")

    path
  end
end
