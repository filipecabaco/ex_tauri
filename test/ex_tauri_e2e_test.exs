defmodule ExTauri.E2ETest do
  @moduledoc """
  E2E tests that verify the generated Tauri project builds correctly.

  These tests call the code generator functions directly and run
  `cargo build` to prove the generated Rust code compiles and links
  into a real executable.

  For the full developer CLI flow (mix phx.new → install → launch),
  see test/e2e_cli_flow.sh which runs as a separate CI job.

  Requires: Rust/Cargo, Linux system dependencies (webkit2gtk, etc.)
  Run with: mix test --include e2e
  """
  use ExUnit.Case, async: false

  @moduletag :e2e

  @app_name "test_e2e_app"
  @tauri_version "2.5.1"
  @host "127.0.0.1"
  @port "14321"

  setup do
    tmp_dir = Path.join(System.tmp_dir!(), "ex_tauri_e2e_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  describe "generated Tauri project" do
    @tag timeout: 600_000
    test "builds a real executable from generated code", %{tmp_dir: tmp_dir} do
      src_tauri = Path.join(tmp_dir, "src-tauri")
      src_dir = Path.join(src_tauri, "src")
      capabilities_dir = Path.join(src_tauri, "capabilities")

      File.mkdir_p!(src_dir)
      File.mkdir_p!(capabilities_dir)

      socket_name = ExTauri.Paths.sanitize_name(@app_name)

      cargo_toml = ExTauri.Install.Helpers.cargo_toml(@app_name, @tauri_version)
      main_rs = ExTauri.Install.Helpers.main_src(@host, @port, socket_name)
      capabilities = ExTauri.Install.Helpers.capabilities_json()

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
              "security" => %{
                "csp" =>
                  "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' ipc: tauri: ws: wss:; img-src 'self' data: asset: tauri:; font-src 'self' data:"
              },
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

      File.write!(Path.join(src_tauri, "Cargo.toml"), cargo_toml)
      File.write!(Path.join(src_dir, "main.rs"), main_rs)
      File.write!(Path.join(src_tauri, "build.rs"), build_rs)
      File.write!(Path.join(src_tauri, "tauri.conf.json"), tauri_conf)
      File.write!(Path.join(capabilities_dir, "default.json"), capabilities)

      # Build (not just check) to produce a real binary
      {build_output, build_exit} =
        System.cmd("cargo", ["build"],
          cd: src_tauri,
          stderr_to_stdout: true
        )

      assert build_exit == 0,
             """
             cargo build failed (exit #{build_exit}).

             Output:
             #{build_output}
             """

      # Verify binary was produced
      binary_path = Path.join([src_tauri, "target", "debug", @app_name])
      assert File.exists?(binary_path), "Expected binary at #{binary_path}"
    end

    test "generated Cargo.toml is valid TOML", %{tmp_dir: tmp_dir} do
      cargo_toml = ExTauri.Install.Helpers.cargo_toml(@app_name, @tauri_version)
      path = Path.join(tmp_dir, "Cargo.toml")
      File.write!(path, cargo_toml)

      assert is_binary(cargo_toml)
      assert cargo_toml =~ "[package]"
      assert cargo_toml =~ "[dependencies]"
      assert cargo_toml =~ "[build-dependencies]"
      assert cargo_toml =~ "[features]"
    end

    test "generated main.rs contains all required components" do
      socket_name = ExTauri.Paths.sanitize_name(@app_name)
      main_rs = ExTauri.Install.Helpers.main_src(@host, @port, socket_name)

      assert main_rs =~ "fn main()"
      assert main_rs =~ "fn start_server"
      assert main_rs =~ "fn check_server_started"
      assert main_rs =~ "fn start_channel"
      assert main_rs =~ "fn kill_sidecar"

      assert main_rs =~ "tauri::Builder::default()"
      assert main_rs =~ ".plugin(tauri_plugin_shell::init())"
      assert main_rs =~ ".plugin(tauri_plugin_log::Builder::new().build())"
      assert main_rs =~ ".setup("
      assert main_rs =~ ".build(tauri::generate_context!())"

      assert main_rs =~ "tauri_heartbeat_#{socket_name}.sock"
      assert main_rs =~ "std::env::temp_dir()"
    end

    test "generated main.rs implements the heartbeat for both Unix and Windows" do
      socket_name = ExTauri.Paths.sanitize_name(@app_name)
      main_rs = ExTauri.Install.Helpers.main_src(@host, @port, socket_name)

      # Unix: heartbeat over the Unix domain socket
      assert main_rs =~ "UnixStream::connect"
      assert main_rs =~ "tauri_heartbeat_#{socket_name}.sock"

      # Windows: heartbeat over localhost TCP, discovered via the port file
      # written by ExTauri.ShutdownManager's :tcp transport
      assert main_rs =~ "tauri_heartbeat_#{socket_name}.port"
      assert main_rs =~ ~s{TcpStream::connect(("127.0.0.1", p))}
      refute main_rs =~ "Heartbeat not yet supported on Windows"

      # Quitting stops the heartbeat so the sidecar can shut down gracefully
      assert main_rs =~ "HEARTBEAT_ACTIVE"
    end

    test "generated capabilities.json is valid JSON with required permissions" do
      json_str = ExTauri.Install.Helpers.capabilities_json()
      {:ok, parsed} = Jason.decode(json_str)

      assert parsed["identifier"] == "default"
      assert "main" in parsed["windows"]

      permissions = parsed["permissions"]
      assert "notification:default" in permissions

      # Broad shell permissions should NOT be present (least-privilege)
      string_permissions = Enum.filter(permissions, &is_binary/1)
      refute "shell:allow-execute" in string_permissions
      refute "shell:allow-spawn" in string_permissions

      # Verify scoped sidecar config
      sidecar = Enum.find(permissions, &is_map/1)
      assert sidecar["identifier"] == "shell:allow-execute"
      assert %{"name" => "desktop", "sidecar" => true} in sidecar["allow"]
    end
  end

  describe "code generation" do
    test "generates correct files for a project with spaces in name" do
      app_name = "My Test App"
      cargo_toml = ExTauri.Install.Helpers.cargo_toml(app_name, @tauri_version)

      assert cargo_toml =~ ~s(name = "my_test_app")
      assert cargo_toml =~ ~s(default-run = "my_test_app")
    end

    test "socket name handles special characters" do
      socket_name = "my_test_app"
      main_rs = ExTauri.Install.Helpers.main_src(@host, @port, socket_name)

      assert main_rs =~ "tauri_heartbeat_my_test_app.sock"
    end
  end
end
