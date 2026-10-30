defmodule Mix.Tasks.ExTauri.Ios do
  @moduledoc """
  Builds the app for iPhone and iPad, and runs it in the iOS simulator or on a
  device.

  ## Usage

      $ mix ex_tauri.ios init          # once: prepare src-tauri for iOS
      $ mix ex_tauri.ios run           # stage the backend, build, run in the simulator
      $ mix ex_tauri.ios device        # stage the backend, build, install and run on an iPhone or iPad
      $ mix ex_tauri.ios dev           # the simulator on your dev server, live reload
      $ mix ex_tauri.ios build         # build for the simulator, without running it

  ## Options

    * `--device NAME|UDID` — the simulator (`run`, `dev`) or the iPhone or iPad
      (`device`) to use. A simulator defaults to one already booted, else the
      first iPad (`xcrun simctl list devices`); a device to the first one
      connected (`xcrun devicectl list devices`).
    * `--console` — stay attached and print the app's output (`run`, `dev`,
      `device`).
    * `--force` — `init` replaces a `src-tauri/src/lib.rs` or `build.rs` it did
      not write, and regenerates the Xcode project.
    * `--allow-older-runtime` — build even when the newest installed simulator
      runtime is older than Xcode's simulator SDK. `cargo tauri ios build`
      refuses that pairing although the app runs fine on the older runtime;
      this reports the installed runtime as the SDK's version to that one check.

  ## How the app runs

  iOS lets an app start no other process, and a device maps no executable
  memory, so the backend runs inside the app. `init` writes an iOS shell to
  `src-tauri/src/lib.rs` and a `src-tauri/build.rs` that links ERTS in. `run`
  and `device` build the release and stage it with `ampoule pack --target ios`
  (see `ExTauri.Packager.package_ios/1`): the release the bundle carries and
  `liberlang.xcframework`, ERTS for the simulator and devices. The shell boots
  the release by calling `erl_start` on a thread of its own, and points its
  window at it. The desktop build is untouched: it still starts in `main.rs`,
  with whichever packager is configured.

  `dev` builds the shell without a backend and launches it pointed at the dev
  server from `config :ex_tauri, :dev_command` on `:host`/`:port`, which it then
  runs in the foreground: the simulator shares the Mac's loopback, so live
  reload works as in a browser.

  ## Requirements

  Xcode with an iOS simulator runtime, the Rust iOS targets
  (`rustup target add aarch64-apple-ios aarch64-apple-ios-sim`), and for `run`
  and `device` ampoule 0.1.9 or later with its iOS runtime, and OTP 28 (see
  `ExTauri.Packager`). `device` also needs the app signed: an Apple ID in Xcode
  and its team in `tauri.ios.conf.json` (`bundle.iOS.developmentTeam`), and the
  device paired with Developer Mode on.
  """

  @shortdoc "Builds and runs the app in the iOS simulator or on a device"

  use Mix.Task

  alias ExTauri.Ios

  @switches [force: :boolean, device: :string, console: :boolean, allow_older_runtime: :boolean]

  @impl true
  def run(args) do
    {opts, rest} = OptionParser.parse!(args, strict: @switches)
    ExTauri.TaskHelpers.preflight_check!(otp: false)

    case rest do
      ["init"] -> init(opts)
      ["build"] -> build(opts, :simulator, backend: true)
      ["run"] -> opts |> build(:simulator, backend: true) |> launch(opts, [])
      ["device"] -> opts |> build(:device, backend: true) |> launch_on_device(opts)
      ["dev"] -> dev(opts)
      _ -> Mix.raise("Usage: mix ex_tauri.ios init|build|run|device|dev [options]")
    end
  end

  defp init(opts) do
    write_lib_rs(opts)
    write_build_rs(opts)

    update_file("src-tauri/Cargo.toml", &Ios.mobile_cargo_toml/1)

    base = base_conf()

    existing =
      if File.exists?("src-tauri/tauri.ios.conf.json"),
        do: read_json("src-tauri/tauri.ios.conf.json"),
        else: %{}

    write_json("src-tauri/tauri.ios.conf.json", Ios.ios_conf(base, existing))
    # Written once: it is the app's to restyle, and rerunning init keeps it.
    unless File.exists?("src-tauri/mobile/index.html") do
      File.mkdir_p!("src-tauri/mobile")

      File.write!(
        "src-tauri/mobile/index.html",
        Ios.loading_page(base["productName"] || "the app")
      )
    end

    if opts[:force] || not File.dir?("src-tauri/gen/apple") do
      ExTauri.run_simple(["ios", "init", "--ci"])
    end

    prepare_xcode_project()

    Mix.shell().info("""

    iOS ready. Run it with:

        mix ex_tauri.ios run       # in the simulator, as it would ship
        mix ex_tauri.ios device    # on an iPhone or iPad
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

  defp write_build_rs(opts) do
    path = "src-tauri/build.rs"
    existing = if File.exists?(path), do: File.read!(path)

    action = if opts[:force], do: :write, else: Ios.build_rs_action(existing)

    case action do
      :write ->
        File.write!(path, Ios.build_rs())
        Mix.shell().info("* wrote #{path}")

      {:refuse, reason} ->
        Mix.raise(reason)
    end
  end

  # Returns what launching needs: the built app (or .ipa) and its bundle identifier.
  defp build(opts, kind, backend: backend?) do
    unless File.read!("src-tauri/src/lib.rs" |> ensure_exists()) =~ "ex_tauri:mobile-shell" do
      Mix.raise("src-tauri is not prepared for iOS yet. Run: mix ex_tauri.ios init")
    end

    host = ExTauri.host_triplet()

    simulator_target =
      case Ios.simulator_target(host) do
        {:ok, target} -> target
        {:error, message} -> Mix.raise(message)
      end

    base = base_conf()
    ios = read_json("src-tauri/tauri.ios.conf.json")
    name = base["productName"] || Mix.raise("tauri.conf.json has no productName")

    if kind == :device, do: check_signing!(ios)

    if backend? do
      ExTauri.TaskHelpers.check_otp_version(:ampoule)
      ExTauri.Packager.package_ios(Ios.stage_dir())
    else
      # `dev` runs no backend, but the bundle still lists the release as a resource.
      File.mkdir_p!(Ios.release_dir())
    end

    # A project generated before the minimum was pinned keeps the old one, and
    # Xcode may have turned script sandboxing back on since.
    prepare_xcode_project()

    # Xcode's build phase runs `cargo tauri ios xcode-script`, so the CLI ex_tauri
    # installed has to be on PATH as a cargo subcommand.
    path =
      shim_dirs(opts, kind) ++
        [Path.join(ExTauri.installation_path(), "bin"), System.get_env("PATH", "")]

    target_args = if kind == :simulator, do: ["--target", simulator_target], else: []

    ExTauri.run_simple(["ios", "build"] ++ target_args ++ ["--debug", "--ci"], [
      {"PATH", Enum.join(path, ":")}
    ])

    built =
      case kind do
        :simulator ->
          Path.join(["src-tauri/gen/apple/build", Ios.app_dir(simulator_target), name <> ".app"])

        :device ->
          Path.join(["src-tauri/gen/apple/build/arm64", name <> ".ipa"])
      end

    File.exists?(built) || Mix.raise("the build reported success but #{built} is missing")
    Mix.shell().info("Built #{built}")

    %{app: built, bundle_id: Ios.bundle_id(base, ios)}
  end

  # A device only runs a signed app; without a team the build fails deep inside
  # Xcode, so say what is needed first.
  defp check_signing!(ios) do
    team =
      get_in(ios, ["bundle", "iOS", "developmentTeam"]) ||
        System.get_env("APPLE_DEVELOPMENT_TEAM")

    unless team do
      Mix.raise("""
      A device only runs a signed app, and no signing team is set.

      Add your Apple ID in Xcode (Settings > Accounts; a free Personal Team works,
      its installs last 7 days), then put its team ID in src-tauri/tauri.ios.conf.json:

          "bundle": { "iOS": { "developmentTeam": "ABCDE12345" } }

      or set APPLE_DEVELOPMENT_TEAM. Xcode shows the ID once the team is picked
      under the target's Signing & Capabilities.
      """)
    end
  end

  defp dev(opts) do
    built = build(opts, :simulator, backend: false)

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

  defp launch_on_device(%{app: ipa, bundle_id: bundle_id}, opts) do
    json =
      Path.join(System.tmp_dir!(), "ex_tauri_devices_#{System.unique_integer([:positive])}.json")

    xcrun!(["devicectl", "list", "devices", "--json-output", json])
    devices = json |> File.read!() |> Jason.decode!()
    File.rm(json)

    device =
      case Ios.pick_physical_device(devices, opts[:device]) do
        {:ok, device} -> device
        {:error, message} -> Mix.raise(message)
      end

    udid = Ios.device_udid(device)
    Mix.shell().info("Installing on #{Ios.device_name(device)} (#{udid})")
    devicectl!(["device", "install", "app", "--device", udid, ipa])

    console = if opts[:console], do: ["--console"], else: []

    {_, status} =
      System.cmd(
        "xcrun",
        ["devicectl", "device", "process", "launch", "--device", udid, "--terminate-existing"] ++
          console ++ [bundle_id],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    status == 0 ||
      Mix.raise("""
      The app is installed but did not launch (devicectl exited #{status}). A locked
      device refuses to launch apps: unlock it and open the app. The first time,
      trust the developer in Settings > General > VPN & Device Management.
      """)
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
  # was allowed; otherwise a clear refusal instead of cargo-mobile2's. A device
  # build checks no simulator runtime.
  defp shim_dirs(_opts, :device), do: []

  defp shim_dirs(opts, :simulator) do
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

  defp devicectl!(args) do
    case System.cmd("xcrun", ["devicectl" | args], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      {output, status} ->
        hint =
          if output =~ ~r/locked/i,
            do: "\nThe device is locked: unlock it, keep it on the home screen, and try again.",
            else: ""

        Mix.raise("xcrun devicectl #{Enum.join(args, " ")} failed (#{status}):\n#{output}#{hint}")
    end
  end

  defp prepare_xcode_project do
    ["src-tauri/gen/apple/project.yml", "src-tauri/gen/apple/*.xcodeproj/project.pbxproj"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.each(
      &update_file(&1, fn text ->
        text |> Ios.raise_deployment_target() |> Ios.allow_build_script()
      end)
    )
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
