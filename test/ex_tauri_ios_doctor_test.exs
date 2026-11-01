defmodule ExTauri.Ios.DoctorTest do
  use ExUnit.Case, async: true

  alias ExTauri.Ios.Doctor

  setup do
    root = Path.join(System.tmp_dir!(), "ex_tauri_doctor_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  defp write!(root, path, contents) do
    path = Path.join(root, path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, contents)
  end

  defp rules(root), do: root |> Doctor.check() |> Enum.map(&{&1.level, &1.rule}) |> Enum.uniq()

  test "a clean project has nothing to report", %{root: root} do
    write!(root, "lib/app.ex", "defmodule App do\n  def dir, do: ExTauri.Paths.data_dir()\nend\n")
    assert Doctor.check(root) == []
  end

  test "a framework without its permission key is an error", %{root: root} do
    write!(
      root,
      "src-tauri/plugins/radio/ios/Sources/R.swift",
      "import CoreBluetooth\nimport MultipeerConnectivity\n"
    )

    write!(
      root,
      "src-tauri/Info.ios.plist",
      "<plist><dict><key>NSBonjourServices</key><array/></dict></plist>"
    )

    messages = root |> Doctor.check() |> Enum.map(& &1.message)
    assert Enum.any?(messages, &(&1 =~ "NSBluetoothAlwaysUsageDescription"))
    assert Enum.any?(messages, &(&1 =~ "NSLocalNetworkUsageDescription"))
    refute Enum.any?(messages, &(&1 =~ "no NSBonjourServices"))
    assert {:error, :permission} in rules(root)
  end

  test "a framework that needs a symbol to need a key", %{root: root} do
    write!(
      root,
      "src-tauri/plugins/p/ios/Sources/P.swift",
      "import AVFoundation\nlet player = AVPlayer()\n"
    )

    assert Doctor.check(root) == []

    write!(
      root,
      "src-tauri/plugins/p/ios/Sources/P.swift",
      "import AVFoundation\nAVCaptureDevice.default(for: .video)\n"
    )

    assert [%{message: message}] = Doctor.check(root)
    assert message =~ "NSCameraUsageDescription"
  end

  test "processes and the home directory, but not in comments", %{root: root} do
    write!(root, "lib/app.ex", """
    defmodule App do
      # System.cmd("never", [])
      def run, do: System.cmd("ls", [])
      def home, do: Path.join(System.user_home!(), "x")
    end
    """)

    assert [
             %{rule: :process, message: "lib/app.ex:3 " <> _},
             %{rule: :home, message: "lib/app.ex:4 " <> _}
           ] = Doctor.check(root)
  end

  test "native code in a dependency", %{root: root} do
    write!(root, "deps/exqlite/c_src/sqlite3.c", "")

    write!(
      root,
      "deps/rusty/mix.exs",
      "defmodule Rusty.MixProject do\n  use Rustler, otp_app: :rusty\nend\n"
    )

    write!(root, "deps/plain/mix.exs", "defmodule Plain.MixProject do\nend\n")

    assert root
           |> Doctor.check()
           |> Enum.map(& &1.message)
           |> Enum.map(&hd(String.split(&1, " has"))) ==
             ["dependency exqlite", "dependency rusty"]
  end

  test "a bridged plugin the app never starts ExTauri.Native for", %{root: root} do
    write!(
      root,
      "src-tauri/plugins/near-radio/ios/Sources/N.swift",
      ~s{let native = ExTauriNative(channel: "near-radio")\n}
    )

    assert [{:warning, :bridge}] = rules(root)

    write!(root, "lib/app.ex", "children = [ExTauri.Native]\n")
    assert Doctor.check(root) == []
  end
end
