defmodule ExTauri.PluginsTest do
  use ExUnit.Case, async: true

  alias ExTauri.Plugins

  # Builds a minimal src-tauri project (the parts ExTauri.Plugins patches)
  # in a unique tmp dir per test.
  setup do
    base_dir =
      Path.join(System.tmp_dir!(), "ex_tauri_plugins_test_#{System.unique_integer([:positive])}")

    src_tauri = Path.join(base_dir, "src-tauri")
    File.mkdir_p!(Path.join(src_tauri, "src"))
    File.mkdir_p!(Path.join(src_tauri, "capabilities"))

    File.write!(Path.join(src_tauri, "Cargo.toml"), """
    [package]
    name = "test_app"
    version = "0.1.0"

    [dependencies]
    tauri = { version = "2", features = [] }
    tauri-plugin-shell = "2"

    [features]
    custom-protocol = [ "tauri/custom-protocol" ]
    """)

    File.write!(Path.join([src_tauri, "src", "main.rs"]), """
    fn main() {
        tauri::Builder::default()
            .plugin(tauri_plugin_shell::init())
            .run(tauri::generate_context!())
            .expect("error");
    }
    """)

    File.write!(
      Path.join([src_tauri, "capabilities", "default.json"]),
      Jason.encode!(%{
        "identifier" => "default",
        "windows" => ["main"],
        "permissions" => ["notification:default"]
      })
    )

    on_exit(fn -> File.rm_rf!(base_dir) end)

    %{base_dir: base_dir, src_tauri: src_tauri}
  end

  defp cargo(ctx), do: File.read!(Path.join(ctx.src_tauri, "Cargo.toml"))
  defp main_rs(ctx), do: File.read!(Path.join([ctx.src_tauri, "src", "main.rs"]))

  defp permissions(ctx) do
    [ctx.src_tauri, "capabilities", "default.json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("permissions")
  end

  describe "registry" do
    test "knows the documented plugins" do
      for name <- ~w(dialog fs clipboard os global-shortcut autostart process updater window) do
        assert name in Plugins.known(), "missing plugin: #{name}"
      end
    end

    test "normalize/1 resolves aliases and rejects unknowns" do
      assert Plugins.normalize("dialog") == "dialog"
      assert Plugins.normalize("DIALOG") == "dialog"
      assert Plugins.normalize("clipboard-manager") == "clipboard"
      assert Plugins.normalize("global_shortcut") == "global-shortcut"
      assert Plugins.normalize("filesystem") == "fs"
      assert Plugins.normalize("app") == "process"
      assert Plugins.normalize("nonsense") == nil
    end

    test "every crate-backed plugin has an init and permissions" do
      for name <- Plugins.known() do
        spec = Plugins.spec(name)
        assert spec.permissions != [], "#{name} has no permissions"
        assert is_binary(spec.api)

        if spec.crate do
          assert spec.init =~ "tauri_plugin_", "#{name} has a crate but no init call"
        end
      end
    end
  end

  describe "add!/2" do
    test "adds Cargo dependency, plugin init, and permissions", ctx do
      Plugins.add!(["dialog"], ctx.base_dir)

      assert cargo(ctx) =~ ~s(tauri-plugin-dialog = "2")
      assert main_rs(ctx) =~ ".plugin(tauri_plugin_dialog::init())"
      assert "dialog:default" in permissions(ctx)
    end

    test "keeps existing content intact", ctx do
      Plugins.add!(["fs"], ctx.base_dir)

      assert cargo(ctx) =~ ~s(tauri-plugin-shell = "2")
      assert main_rs(ctx) =~ ".plugin(tauri_plugin_shell::init())"
      assert "notification:default" in permissions(ctx)
    end

    test "is idempotent", ctx do
      Plugins.add!(["dialog"], ctx.base_dir)
      before_cargo = cargo(ctx)
      before_main = main_rs(ctx)
      before_perms = permissions(ctx)

      Plugins.add!(["dialog"], ctx.base_dir)

      assert cargo(ctx) == before_cargo
      assert main_rs(ctx) == before_main
      assert permissions(ctx) == before_perms
    end

    test "installs several plugins at once", ctx do
      Plugins.add!(["dialog", "fs", "clipboard"], ctx.base_dir)

      assert cargo(ctx) =~ "tauri-plugin-dialog"
      assert cargo(ctx) =~ "tauri-plugin-fs"
      assert cargo(ctx) =~ "tauri-plugin-clipboard-manager"
      assert "dialog:default" in permissions(ctx)
      assert "fs:default" in permissions(ctx)
      assert "clipboard-manager:allow-read-text" in permissions(ctx)
    end

    test "window pseudo-plugin only touches capabilities", ctx do
      before_cargo = cargo(ctx)
      before_main = main_rs(ctx)

      Plugins.add!(["window"], ctx.base_dir)

      assert cargo(ctx) == before_cargo
      assert main_rs(ctx) == before_main
      assert "core:default" in permissions(ctx)
      assert "core:window:allow-set-title" in permissions(ctx)
    end

    test "autostart uses the MacosLauncher init form", ctx do
      Plugins.add!(["autostart"], ctx.base_dir)

      assert main_rs(ctx) =~
               ".plugin(tauri_plugin_autostart::init(tauri_plugin_autostart::MacosLauncher::LaunchAgent, None))"
    end

    test "raises on unknown plugin names", ctx do
      assert_raise RuntimeError, ~r/Unknown Tauri plugin/, fn ->
        Plugins.add!(["not-a-plugin"], ctx.base_dir)
      end
    end

    test "raises when src-tauri is missing" do
      empty_dir =
        Path.join(System.tmp_dir!(), "ex_tauri_no_src_#{System.unique_integer([:positive])}")

      File.mkdir_p!(empty_dir)
      on_exit(fn -> File.rm_rf!(empty_dir) end)

      assert_raise RuntimeError, ~r/Could not find src-tauri/, fn ->
        Plugins.add!(["dialog"], empty_dir)
      end
    end

    test "generated main.rs from the template accepts plugin injection", ctx do
      # The real template's builder chain must contain the anchor add!/2 uses.
      main_rs = ExTauri.Install.Helpers.main_src("localhost", "4000", "test_app")
      File.write!(Path.join([ctx.src_tauri, "src", "main.rs"]), main_rs)

      Plugins.add!(["dialog"], ctx.base_dir)

      updated = main_rs(ctx)
      assert updated =~ "tauri::Builder::default()\n        .plugin(tauri_plugin_dialog::init())"
    end
  end
end
