defmodule ExTauri.IosPluginsTest do
  use ExUnit.Case, async: true

  alias ExTauri.Ios
  alias ExTauri.Install.Helpers

  @toml """
  [package]
  name = "app"

  [dependencies]
  tauri = { version = "2" }
  """

  setup do
    dir =
      Path.join(System.tmp_dir!(), "ex_tauri_ios_plugins_#{System.unique_integer([:positive])}")

    on_exit(fn -> File.rm_rf!(dir) end)
    %{src_tauri: dir}
  end

  defp scaffold!(src_tauri, name) do
    for {path, contents} <- Ios.plugin_scaffold(name) do
      target = Path.join([src_tauri, "plugins", name, path])
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, contents)
    end
  end

  test "finds scaffolded plugins and configured crates", %{src_tauri: src_tauri} do
    scaffold!(src_tauri, "near-radio")
    File.mkdir_p!(Path.join(src_tauri, "plugins/not-a-plugin"))

    assert [
             %{crate: "tauri-plugin-ex-tauri", dep: shell_dep},
             %{
               crate: "tauri-plugin-near-radio",
               dep: ~s(tauri-plugin-near-radio = { path = "plugins/near-radio" }),
               init: "tauri_plugin_near_radio::init()"
             },
             %{crate: "tauri-plugin-haptics", dep: ~s(tauri-plugin-haptics = "2")},
             %{crate: "tauri-plugin-x", init: "tauri_plugin_x::Builder::new().build()"}
           ] =
             Ios.ios_plugins(src_tauri, [
               {"tauri-plugin-haptics", "2"},
               {"tauri-plugin-x", path: "../x", init: "tauri_plugin_x::Builder::new().build()"}
             ])

    # ex_tauri's own plugin, from the dependency, by a path relative to src-tauri.
    [_, path] = Regex.run(~r/path = "([^"]+)"/, shell_dep)

    assert File.exists?(
             Path.expand(Path.join([src_tauri, path, "ios/Sources/ExTauriShell.swift"]))
           )
  end

  test "ex_tauri's own plugin is configured from :ios" do
    assert Ios.shell_plugin_config([]) == %{
             "formAccessoryBar" => false,
             "dismissKeyboardOnSwipe" => true,
             "keyboardResize" => true,
             "appLikePage" => true
           }

    assert Ios.shell_plugin_config(form_accessory_bar: true)["formAccessoryBar"]
    assert Ios.ios_conf(%{})["plugins"]["ex-tauri"] == Ios.shell_plugin_config()
  end

  test "refuses a crate name that is not one" do
    assert_raise ArgumentError, fn -> Ios.ios_plugins("nowhere", [{"x\"; evil", "2"}]) end
  end

  test "plugin deps get an iOS-only table, replaced on every run" do
    one = [%{crate: "a", dep: ~s(a = "2"), init: "a::init()"}]
    two = one ++ [%{crate: "b", dep: ~s(b = { path = "plugins/b" }), init: "b::init()"}]

    once = Ios.ios_plugin_deps(@toml, two)

    assert once =~
             "[target.'cfg(target_os = \"ios\")'.dependencies]\na = \"2\"\nb = { path = \"plugins/b\" }\n"

    assert Ios.ios_plugin_deps(once, two) == once

    fewer = Ios.ios_plugin_deps(once, one)
    refute fewer =~ "plugins/b"
    assert Ios.ios_plugin_deps(fewer, []) |> String.trim() == String.trim(@toml)
  end

  test "keeps what follows the table" do
    toml =
      Ios.ios_plugin_deps(@toml, [%{crate: "a", dep: ~s(a = "2"), init: "a::init()"}]) <>
        "\n[features]\nx = []\n"

    assert Ios.ios_plugin_deps(toml, []) =~ "[features]\nx = []"
  end

  test "the shell registers each plugin, on iOS only" do
    src =
      Helpers.mobile_src("localhost", "http", [
        %{crate: "a", dep: "", init: "tauri_plugin_a::init()"}
      ])

    assert src =~
             ~s{#[cfg(target_os = "ios")]\n        let builder = builder.plugin(tauri_plugin_a::init());}

    assert :write = Ios.lib_rs_action(src)
    refute Helpers.mobile_src("localhost") =~ ".plugin("
  end

  test "a scaffolded plugin is wired to its channel" do
    files = Map.new(Ios.plugin_scaffold("near-radio"))

    assert files["Cargo.toml"] =~ ~s(name = "tauri-plugin-near-radio")
    assert files["Cargo.toml"] =~ ~s(links = "tauri-plugin-near-radio")
    assert files["src/lib.rs"] =~ "ios_plugin_binding!(init_plugin_near_radio)"
    assert files["ios/Sources/NearRadioPlugin.swift"] =~ ~s{@_cdecl("init_plugin_near_radio")}
    assert files["ios/Sources/NearRadioPlugin.swift"] =~ ~s{ExTauriNative(channel: "near-radio")}
    assert files["ios/Sources/ExTauriNative.swift"] == Ios.native_swift()
    assert files["ios/Package.swift"] =~ ~s{path: "../.tauri/tauri-api"}
  end

  test "plugin names are lowercase words joined by dashes" do
    assert Ios.valid_plugin_name?("near-radio")

    for bad <- ["Near", "near_radio", "-x", "x-", "a--b", "1x", ""],
        do: refute(Ios.valid_plugin_name?(bad))
  end

  test "ex-tauri is taken by ex_tauri's own plugin" do
    refute Ios.valid_plugin_name?("ex-tauri")
  end

  test "the Swift bridge reads the handoff path ExTauri.Native writes" do
    assert Ios.native_swift() =~ ~s{"/Library/Application Support/ex_tauri/native.json"}

    assert ExTauri.Native.handoff_path()
           |> String.ends_with?("Library/Application Support/ex_tauri/native.json")
  end
end
