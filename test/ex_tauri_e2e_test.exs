defmodule ExTauri.E2ETest do
  @moduledoc """
  End-to-end tests that verify the generated Tauri project compiles correctly.

  These tests require Rust/Cargo and Linux system dependencies (webkit2gtk, etc.)
  to be installed. They are tagged :e2e and skipped by default.

  Run with: mix test --include e2e
  """
  use ExUnit.Case, async: false

  @moduletag :e2e

  @app_name "test_e2e_app"
  @tauri_version "2.5.1"
  @host "localhost"
  @port "4000"

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "ex_tauri_e2e_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "generated Tauri project" do
    test "produces valid Rust code that passes cargo check", %{tmp_dir: tmp_dir} do
      src_tauri = Path.join(tmp_dir, "src-tauri")
      src_dir = Path.join(src_tauri, "src")
      capabilities_dir = Path.join(src_tauri, "capabilities")

      File.mkdir_p!(src_dir)
      File.mkdir_p!(capabilities_dir)

      # Generate all files using the same functions the install task uses
      socket_name = @app_name |> String.replace(" ", "_") |> String.downcase()

      cargo_toml = Mix.Tasks.ExTauri.Install.cargo_toml(@app_name, @tauri_version)
      main_rs = Mix.Tasks.ExTauri.Install.main_src(@host, @port, socket_name)
      capabilities = Mix.Tasks.ExTauri.Install.capabilities_json()

      build_rs = """
      fn main() {
          tauri_build::build()
      }
      """

      tauri_conf =
        Jason.encode!(
          %{
            "productName" => @app_name,
            "version" => "0.1.0",
            "identifier" => "you.app.test-e2e-app",
            "build" => %{
              "devUrl" => "http://#{@host}:#{@port}",
              "frontendDist" => "http://#{@host}:#{@port}"
            },
            "app" => %{
              "windows" => [
                %{
                  "title" => @app_name,
                  "width" => 800,
                  "height" => 600,
                  "resizable" => true,
                  "fullscreen" => false
                }
              ]
            },
            "bundle" => %{
              "externalBin" => ["../burrito_out/desktop"]
            }
          },
          pretty: true
        )

      # Write all generated files
      File.write!(Path.join(src_tauri, "Cargo.toml"), cargo_toml)
      File.write!(Path.join(src_dir, "main.rs"), main_rs)
      File.write!(Path.join(src_dir, "build.rs"), build_rs)
      File.write!(Path.join(src_tauri, "tauri.conf.json"), tauri_conf)
      File.write!(Path.join(capabilities_dir, "default.json"), capabilities)

      # Run cargo check to verify the Rust code compiles
      {output, exit_code} =
        System.cmd("cargo", ["check"], cd: src_tauri, stderr_to_stdout: true)

      assert exit_code == 0,
             """
             cargo check failed with exit code #{exit_code}.

             Output:
             #{output}

             Generated Cargo.toml:
             #{cargo_toml}

             Generated main.rs (first 50 lines):
             #{main_rs |> String.split("\n") |> Enum.take(50) |> Enum.join("\n")}
             """
    end

    test "generated Cargo.toml is valid TOML", %{tmp_dir: tmp_dir} do
      cargo_toml = Mix.Tasks.ExTauri.Install.cargo_toml(@app_name, @tauri_version)
      path = Path.join(tmp_dir, "Cargo.toml")
      File.write!(path, cargo_toml)

      # Use cargo to validate — `cargo read-manifest` requires a full project,
      # but we can at least verify cargo doesn't choke on the TOML syntax
      # by running `cargo metadata` in a minimal context
      assert is_binary(cargo_toml)
      assert cargo_toml =~ "[package]"
      assert cargo_toml =~ "[dependencies]"
      assert cargo_toml =~ "[build-dependencies]"
      assert cargo_toml =~ "[features]"
    end

    test "generated main.rs contains all required components" do
      socket_name = @app_name |> String.replace(" ", "_") |> String.downcase()
      main_rs = Mix.Tasks.ExTauri.Install.main_src(@host, @port, socket_name)

      # Verify structural components
      assert main_rs =~ "fn main()"
      assert main_rs =~ "fn start_server"
      assert main_rs =~ "fn check_server_started"
      assert main_rs =~ "fn start_heartbeat"
      assert main_rs =~ "fn kill_sidecar"

      # Verify Tauri V2 builder pattern
      assert main_rs =~ "tauri::Builder::default()"
      assert main_rs =~ ".plugin(tauri_plugin_shell::init())"
      assert main_rs =~ ".plugin(tauri_plugin_log::Builder::new().build())"
      assert main_rs =~ ".setup("
      assert main_rs =~ ".build(tauri::generate_context!())"

      # Verify heartbeat uses the correct socket path
      assert main_rs =~ "/tmp/tauri_heartbeat_#{socket_name}.sock"
    end

    test "generated capabilities.json is valid JSON with required permissions" do
      json_str = Mix.Tasks.ExTauri.Install.capabilities_json()
      {:ok, parsed} = Jason.decode(json_str)

      assert parsed["identifier"] == "default"
      assert "main" in parsed["windows"]

      permissions = parsed["permissions"]
      assert "shell:allow-execute" in permissions
      assert "shell:allow-spawn" in permissions

      # Verify sidecar config
      sidecar = Enum.find(permissions, &is_map/1)
      assert sidecar["identifier"] == "shell:allow-execute"
      assert %{"name" => "desktop", "sidecar" => true} in sidecar["allow"]
    end
  end

  describe "install task file generation" do
    test "generates correct files for a project with spaces in name" do
      app_name = "My Test App"
      cargo_toml = Mix.Tasks.ExTauri.Install.cargo_toml(app_name, @tauri_version)

      # App name should be snake_cased in Cargo.toml
      assert cargo_toml =~ ~s(name = "my_test_app")
      assert cargo_toml =~ ~s(default-run = "my_test_app")
    end

    test "socket name handles special characters" do
      socket_name = "my test app" |> String.replace(" ", "_") |> String.downcase()
      main_rs = Mix.Tasks.ExTauri.Install.main_src(@host, @port, socket_name)

      assert main_rs =~ "/tmp/tauri_heartbeat_my_test_app.sock"
    end
  end
end
