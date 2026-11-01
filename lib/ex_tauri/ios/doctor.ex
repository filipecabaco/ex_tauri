defmodule ExTauri.Ios.Doctor do
  @moduledoc """
  Checks an app against the rules of an iOS build (`guides/ios.md`, "Rules for a
  mobile app"): what ex_tauri cannot fix for the app, it at least points out
  before a device does.

  `mix ex_tauri.ios doctor` prints the findings; `init`, `run` and `device` run it
  too, and `run` and `device` stop on an error (`--skip-doctor` builds anyway).

    * **error** — a native plugin uses a framework whose permission key is not in
      `src-tauri/Info.ios.plist`: iOS ends the app the first time it is used.
    * **warning** — code that cannot work inside the app (starting processes,
      writing under the home directory, native code in a dependency), or a native
      plugin the app never talks to.
  """

  @type finding :: %{level: :error | :warning, rule: atom(), message: String.t()}

  # A framework a plugin imports (and, where importing it is not enough, a symbol
  # it uses), and the Info.plist keys iOS requires before it may be used.
  @permissions [
    {"CoreBluetooth", nil, ~w(NSBluetoothAlwaysUsageDescription)},
    {"MultipeerConnectivity", nil, ~w(NSLocalNetworkUsageDescription NSBonjourServices)},
    {"Network", ~r/NWBrowser|NWListener|includePeerToPeer/, ~w(NSLocalNetworkUsageDescription)},
    {"CoreLocation", nil, ~w(NSLocationWhenInUseUsageDescription)},
    {"AVFoundation", ~r/AVCaptureDevice|AVCaptureSession/, ~w(NSCameraUsageDescription)},
    {"AVFoundation", ~r/AVAudioRecorder|requestRecordPermission|AVAudioApplication/,
     ~w(NSMicrophoneUsageDescription)},
    {"Photos", ~r/PHPhotoLibrary/, ~w(NSPhotoLibraryUsageDescription)},
    {"Contacts", nil, ~w(NSContactsUsageDescription)},
    {"HealthKit", nil, ~w(NSHealthShareUsageDescription)},
    {"CoreMotion", nil, ~w(NSMotionUsageDescription)},
    {"Speech", nil, ~w(NSSpeechRecognitionUsageDescription)},
    {"LocalAuthentication", ~r/LAContext/, ~w(NSFaceIDUsageDescription)}
  ]

  @processes ~r/System\.cmd\(|System\.shell\(|Port\.open\(\s*\{:spawn|:os\.cmd\(/
  @home ~r/System\.user_home!?\(|Path\.expand\(\s*"~|"~\//

  @doc "Every finding for the project in `root` (default: the current directory)."
  @spec check(Path.t()) :: [finding()]
  def check(root \\ File.cwd!()) do
    permissions(root) ++ processes(root) ++ home(root) ++ native_deps(root) ++ bridge(root)
  end

  @doc "Prints findings, and answers whether any is an error."
  @spec report([finding()]) :: :ok | :error
  def report([]), do: :ok

  def report(findings) do
    Mix.shell().info("\nmix ex_tauri.ios doctor:")

    for %{level: level, message: message} <- findings do
      tag = if level == :error, do: [:red, "  error  "], else: [:yellow, "  warning"]
      Mix.shell().info([tag, :reset, " ", message])
    end

    Mix.shell().info("  (guides/ios.md, \"Rules for a mobile app\")\n")
    if Enum.any?(findings, &(&1.level == :error)), do: :error, else: :ok
  end

  defp permissions(root) do
    declared = plist_keys(root)

    for file <- swift_sources(root),
        source = File.read!(file),
        {framework, symbol, keys} <- @permissions,
        source =~ ~r/^\s*import\s+#{framework}\b/m,
        symbol == nil or source =~ symbol,
        key <- keys,
        key not in declared,
        uniq: true do
      %{
        level: :error,
        rule: :permission,
        message:
          "#{relative(file, root)} uses #{framework}, but src-tauri/Info.ios.plist has no " <>
            "#{key}: iOS ends the app the first time it is used"
      }
    end
  end

  defp processes(root) do
    for {file, line} <- grep(root, @processes) do
      %{
        level: :warning,
        rule: :process,
        message:
          "#{file}:#{line} starts a process; iOS starts none inside an app (use a native plugin)"
      }
    end
  end

  defp home(root) do
    for {file, line} <- grep(root, @home) do
      %{
        level: :warning,
        rule: :home,
        message:
          "#{file}:#{line} uses the home directory; on a device its root is read-only " <>
            "(use ExTauri.Paths)"
      }
    end
  end

  # A dependency with C or Rust in it: ampoule packs only OTP's own NIFs for iOS.
  defp native_deps(root) do
    for dir <- root |> Path.join("deps/*") |> Path.wildcard() |> Enum.sort(),
        native?(dir) do
      %{
        level: :warning,
        rule: :native_dep,
        message:
          "dependency #{Path.basename(dir)} has native code; only OTP's NIFs run on iOS " <>
            "(`ampoule pack --target ios` refuses it)"
      }
    end
  end

  defp native?(dir) do
    File.dir?(Path.join(dir, "c_src")) or File.exists?(Path.join(dir, "native")) or
      match?({:ok, _}, File.read(Path.join(dir, "mix.exs")) |> rustler_or_make())
  end

  defp rustler_or_make({:ok, mix}) do
    if mix =~ ~r/compilers:\s*\[[^\]]*:(elixir_make|rustler)/ or mix =~ ~r/use Rustler/,
      do: {:ok, mix},
      else: :error
  end

  defp rustler_or_make(_), do: :error

  defp bridge(root) do
    plugins =
      for file <- swift_sources(root),
          File.read!(file) =~ ~r/ExTauriNative\(channel:/,
          do: file |> Path.split() |> Enum.drop_while(&(&1 != "plugins")) |> Enum.at(1)

    used? = grep(root, ~r/ExTauri\.Native\b/) != []

    if plugins != [] and not used? do
      [
        %{
          level: :warning,
          rule: :bridge,
          message:
            "plugin #{plugins |> Enum.uniq() |> Enum.join(", ")} talks over ExTauri.Native, " <>
              "which the app never starts (add ExTauri.Native to its children)"
        }
      ]
    else
      []
    end
  end

  defp swift_sources(root) do
    root
    |> Path.join("src-tauri/plugins/*/ios/Sources/**/*.swift")
    |> Path.wildcard()
    |> Enum.reject(&(Path.basename(&1) == "ExTauriNative.swift"))
  end

  defp plist_keys(root) do
    for file <- ["src-tauri/Info.ios.plist", "src-tauri/Info.plist"],
        {:ok, plist} <- [File.read(Path.join(root, file))],
        [_, key] <- Regex.scan(~r/<key>\s*([A-Za-z0-9_.-]+)\s*<\/key>/, plist),
        uniq: true,
        do: key
  end

  defp grep(root, pattern) do
    for file <- root |> Path.join("lib/**/*.{ex,exs}") |> Path.wildcard() |> Enum.sort(),
        {text, n} <- file |> File.read!() |> String.split("\n") |> Enum.with_index(1),
        not String.starts_with?(String.trim_leading(text), "#"),
        text =~ pattern,
        do: {relative(file, root), n}
  end

  defp relative(file, root), do: Path.relative_to(file, root)
end
