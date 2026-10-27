defmodule ExTauri.Ios do
  @moduledoc """
  The pieces behind `mix ex_tauri.ios`: preparing `src-tauri` for an iOS build,
  packaging the backend for the simulator, and driving the simulator.

  On iOS a Tauri app cannot ship a sidecar, so the generated shell
  (`src-tauri/src/lib.rs`) starts the release itself, packed by ampoule (see
  `ExTauri.Packager`) and bundled as a resource. iOS lets an app do that only in
  the simulator: a device forbids both starting a process and the executable
  memory ampoule's engine maps. The simulator runs Mac binaries, so the backend
  is packed for the Mac's own architecture.
  """

  # Marks a lib.rs this module wrote, so `init` may regenerate it.
  @marker "ex_tauri:mobile-shell"

  # Where `mix ex_tauri.ios build` puts the backend, and where the iOS bundle
  # takes it from (relative to src-tauri, as Tauri resolves resources).
  @backend "burrito_out/ios/backend"
  # The oldest iOS that current Xcode builds for.
  @ios_minimum "15.0"

  @desktop_only ~s{[target.'cfg(not(any(target_os = "android", target_os = "ios")))'.dependencies]}

  @doc "Where the packed backend is written, relative to the project root."
  def backend_path, do: @backend

  @doc """
  What `init` should do with an existing `src-tauri/src/lib.rs`: write it when
  there is none, or when it is the stub `cargo tauri init` leaves (an empty
  mobile entry point nothing calls) or one this module generated; otherwise
  leave it alone.
  """
  @spec lib_rs_action(String.t() | nil) :: :write | {:refuse, String.t()}
  def lib_rs_action(nil), do: :write

  def lib_rs_action(source) do
    cond do
      String.contains?(source, @marker) -> :write
      tauri_stub?(source) -> :write
      true -> {:refuse, "src-tauri/src/lib.rs has code of its own; pass --force to replace it"}
    end
  end

  defp tauri_stub?(source) do
    String.contains?(source, "mobile_entry_point") and
      String.contains?(source, "tauri::Builder::default()") and
      length(String.split(source, "\n")) < 40
  end

  @doc """
  Prepares a Cargo.toml for an iOS build, returning it unchanged when it is
  already prepared:

    * a `[lib]` the iOS build links (`<package>_lib`, as `cargo tauri init`
      names it, so it never collides with the desktop binary);
    * `tauri-plugin-single-instance` moved to a desktop-only table: only the
      desktop `main.rs` uses it, and it does not build for iOS.
  """
  @spec mobile_cargo_toml(String.t()) :: String.t()
  def mobile_cargo_toml(toml) do
    toml
    |> add_lib_section()
    |> move_to_desktop_only("tauri-plugin-single-instance")
  end

  defp add_lib_section(toml) do
    if Regex.match?(~r/^\[lib\]/m, toml) do
      toml
    else
      [_, name] = Regex.run(~r/^\[package\][^\[]*?^name\s*=\s*"([^"]+)"/ms, toml)

      lib = """
      [lib]
      name = "#{name}_lib"
      crate-type = ["staticlib", "cdylib", "rlib"]

      """

      # Right after [package]: before the first header that follows it.
      Regex.replace(~r/(^\[package\].*?)(^\[)/ms, toml, "\\1#{lib}\\2", global: false)
    end
  end

  defp move_to_desktop_only(toml, crate) do
    line = Regex.run(~r/^#{Regex.escape(crate)}\s*=.*\n/m, toml)

    cond do
      is_nil(line) ->
        toml

      already_desktop_only?(toml, crate) ->
        toml

      String.contains?(toml, @desktop_only) ->
        toml
        |> String.replace(hd(line), "", global: false)
        |> String.replace(@desktop_only <> "\n", @desktop_only <> "\n" <> hd(line), global: false)

      true ->
        String.replace(toml, hd(line), "", global: false) <>
          "\n# Desktop only: the iOS build does not use it, and it does not build there.\n" <>
          @desktop_only <> "\n" <> hd(line)
    end
  end

  defp already_desktop_only?(toml, crate) do
    case String.split(toml, @desktop_only, parts: 2) do
      [_, after_header] ->
        after_header |> String.split(~r/^\[/m, parts: 2) |> hd() |> String.contains?(crate)

      _ ->
        false
    end
  end

  @doc """
  `src-tauri/tauri.ios.conf.json`, which Tauri merges over `tauri.conf.json`
  for iOS builds: the backend as a resource instead of a sidecar, a bundled
  loading page instead of the desktop's first URL, and an identifier iOS
  accepts.
  """
  @spec ios_conf(map()) :: map()
  def ios_conf(base) do
    conf = %{
      "build" => %{"frontendDist" => "mobile"},
      "bundle" => %{
        "externalBin" => [],
        "resources" => %{"../#{@backend}" => "ex_tauri/backend"},
        # The Xcode project's IPHONEOS_DEPLOYMENT_TARGET. Tauri CLIs before 2.12
        # default it to 14.0, which Xcode 27 refuses to build for; pinned so the
        # project builds whichever CLI an app has installed.
        "iOS" => %{"minimumSystemVersion" => @ios_minimum}
      }
    }

    # iOS bundle identifiers allow letters, digits, hyphens and dots only.
    case base["identifier"] do
      id when is_binary(id) ->
        if String.contains?(id, "_"),
          do: Map.put(conf, "identifier", String.replace(id, "_", "-")),
          else: conf

      _ ->
        conf
    end
  end

  @doc """
  Raises the iOS minimum in a generated Xcode project (`project.yml` or
  `project.pbxproj`) to the one `ios_conf/1` pins.

  `cargo tauri ios init` writes the project once and leaves it alone after, so a
  project made by a CLI that defaulted to 14.0 keeps it, whatever
  `tauri.ios.conf.json` says now, and Xcode 27 will not build it. Only versions
  below the minimum change; anything an app raised itself is left as it is.
  """
  def raise_deployment_target(text) do
    Regex.replace(
      ~r/(IPHONEOS_DEPLOYMENT_TARGET = |deploymentTarget:\n\s+iOS: )(\d+(?:\.\d+)*)/,
      text,
      fn whole, prefix, version ->
        if Version.compare(semver(version), semver(@ios_minimum)) == :lt,
          do: prefix <> @ios_minimum,
          else: whole
      end
    )
  end

  defp semver(version) do
    parts = version |> String.split(".") |> Enum.map(&String.to_integer/1)
    [major, minor, patch] = Enum.take(parts ++ [0, 0, 0], 3)
    Version.parse!("#{major}.#{minor}.#{patch}")
  end

  @doc "The identifier the iOS app is installed under."
  def bundle_id(base, ios), do: ios["identifier"] || base["identifier"]

  @doc "The page the window shows until the backend answers."
  def loading_page(app_name) do
    """
    <!DOCTYPE html>
    <html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
    <style>body{font-family:-apple-system,system-ui,sans-serif;display:grid;place-items:center;min-height:100vh;margin:0;color:#57534e;background:#fafaf9}@media (prefers-color-scheme:dark){body{color:#d6d3d1;background:#1c1917}}</style>
    </head><body><p>Starting #{escape(app_name)}…</p></body></html>
    """
  end

  defp escape(text),
    do: text |> to_string() |> String.replace("&", "&amp;") |> String.replace("<", "&lt;")

  @doc """
  The `cargo tauri ios build --target` for this Mac, and the Rust triple the
  backend is packed for: the simulator runs the Mac's own binaries.
  """
  @spec simulator_target(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def simulator_target("aarch64-apple-darwin"), do: {:ok, "aarch64-sim"}
  def simulator_target("x86_64-apple-darwin"), do: {:ok, "x86_64"}

  def simulator_target(host),
    do: {:error, "iOS builds need a Mac; this is #{host}"}

  @doc "The directory `cargo tauri ios build` writes the simulator app to."
  def app_dir("aarch64-sim"), do: "arm64-sim"
  def app_dir("x86_64"), do: "x86_64"

  @doc """
  Picks the simulator to run on from `xcrun simctl list devices available
  --json` output: the one named or whose UDID is `wanted`, else one already
  booted, else the first iPad.
  """
  @spec pick_device(map(), String.t() | nil) :: {:ok, map()} | {:error, String.t()}
  def pick_device(%{"devices" => by_runtime}, wanted) do
    devices =
      for {runtime, list} <- by_runtime, String.contains?(runtime, "iOS"), device <- list do
        device
      end

    found =
      if wanted do
        Enum.find(devices, &(&1["udid"] == wanted or &1["name"] == wanted))
      else
        Enum.find(devices, &(&1["state"] == "Booted")) ||
          Enum.find(devices, &String.starts_with?(&1["name"], "iPad"))
      end

    case found do
      nil -> {:error, no_device_message(devices, wanted)}
      device -> {:ok, device}
    end
  end

  defp no_device_message(devices, wanted) do
    names = devices |> Enum.map(& &1["name"]) |> Enum.uniq() |> Enum.join(", ")
    which = if wanted, do: "named #{inspect(wanted)}", else: "to run on"

    "No iOS simulator #{which}. Available: #{if names == "", do: "none", else: names}"
  end

  @doc """
  Whether an installed simulator runtime is at least `sdk`, the version of
  Xcode's simulator SDK. `cargo tauri ios build` refuses to build otherwise,
  even though the app would run on an older runtime.
  """
  @spec runtime_covers_sdk?(map(), String.t()) :: boolean()
  def runtime_covers_sdk?(%{"runtimes" => runtimes}, sdk) do
    Enum.any?(runtimes, fn runtime ->
      runtime["isAvailable"] and String.starts_with?(runtime["identifier"] || "", ios_runtime()) and
        Version.compare(version(runtime["version"]), version(sdk)) != :lt
    end)
  end

  @doc "The newest available iOS simulator runtime's version, if any."
  def newest_runtime(%{"runtimes" => runtimes}) do
    runtimes
    |> Enum.filter(
      &(&1["isAvailable"] and String.starts_with?(&1["identifier"] || "", ios_runtime()))
    )
    |> Enum.map(& &1["version"])
    |> Enum.max_by(&version/1, Version, fn -> nil end)
  end

  defp ios_runtime, do: "com.apple.CoreSimulator.SimRuntime.iOS"

  defp version(text) do
    case text |> String.split(".") |> Enum.map(&String.to_integer/1) do
      [major] -> Version.parse!("#{major}.0.0")
      [major, minor] -> Version.parse!("#{major}.#{minor}.0")
      [major, minor, patch | _] -> Version.parse!("#{major}.#{minor}.#{patch}")
    end
  end

  @doc """
  An `xcrun` that reports the newest installed iOS runtime as `sdk` and passes
  every other call through, for `--allow-older-runtime`. Only the runtime list
  `cargo tauri ios build` checks is changed; nothing is installed.
  """
  def xcrun_shim(runtime, sdk) do
    """
    #!/bin/sh
    # Written by `mix ex_tauri.ios --allow-older-runtime`. cargo-mobile2 refuses
    # to build unless a simulator runtime matches Xcode's default simulator SDK
    # (#{sdk}); the newest installed is #{runtime}. Report it as #{sdk} for that
    # one query and pass everything else to the real xcrun.
    if [ "$*" = "simctl list runtimes --json" ]; then
      /usr/bin/xcrun simctl list runtimes --json | sed 's/"version" : "#{runtime}"/"version" : "#{sdk}"/'
    else
      exec /usr/bin/xcrun "$@"
    fi
    """
  end
end
