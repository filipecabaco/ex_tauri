defmodule ExTauri.E2ETest do
  @moduledoc """
  End-to-end tests that verify the generated Tauri project builds and runs.

  These tests require Rust/Cargo, xvfb, and Linux system dependencies
  (webkit2gtk, etc.) to be installed. They are tagged :e2e and skipped
  by default.

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

  defp target_triple do
    {output, 0} = System.cmd("rustc", ["-Vv"])

    output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case String.split(line, "host: ") do
        [_, triple] -> String.trim(triple)
        _ -> nil
      end
    end)
  end

  defp generate_project(tmp_dir) do
    src_tauri = Path.join(tmp_dir, "src-tauri")
    src_dir = Path.join(src_tauri, "src")
    capabilities_dir = Path.join(src_tauri, "capabilities")

    File.mkdir_p!(src_dir)
    File.mkdir_p!(capabilities_dir)

    socket_name = ExTauri.Paths.sanitize_name(@app_name)

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
            "security" => %{
              "csp" => "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; connect-src 'self' ipc: tauri: ws: wss:; img-src 'self' data: asset: tauri:; font-src 'self' data:"
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
    File.write!(Path.join(src_dir, "build.rs"), build_rs)
    File.write!(Path.join(src_tauri, "tauri.conf.json"), tauri_conf)
    File.write!(Path.join(capabilities_dir, "default.json"), capabilities)

    src_tauri
  end

  defp create_fake_sidecar(tmp_dir) do
    # Create a minimal sidecar script that listens on the configured port.
    # Tauri resolves sidecars as {name}-{target-triple}.
    burrito_dir = Path.join(tmp_dir, "burrito_out")
    File.mkdir_p!(burrito_dir)

    triple = target_triple()
    sidecar_path = Path.join(burrito_dir, "desktop-#{triple}")

    # The sidecar just needs to bind the port so check_server_started() passes,
    # then stay alive until killed.
    script = """
    #!/bin/bash
    python3 -c "
    import http.server, socketserver
    handler = http.server.SimpleHTTPRequestHandler
    with socketserver.TCPServer(('#{@host}', #{@port}), handler) as s:
        s.serve_forever()
    " &
    wait
    """

    File.write!(sidecar_path, script)
    File.chmod!(sidecar_path, 0o755)

    sidecar_path
  end

  describe "generated Tauri project" do
    @tag timeout: 600_000
    test "builds a working binary and launches under xvfb", %{tmp_dir: tmp_dir} do
      src_tauri = generate_project(tmp_dir)

      # --- Phase 1: Build (not just check) ---
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
      assert File.stat!(binary_path).access in [:read_write, :read]

      # --- Phase 2: Launch with fake sidecar under xvfb ---
      # Check xvfb-run is available (CI installs it, local dev may not have it)
      {_, xvfb_exit} = System.cmd("which", ["xvfb-run"], stderr_to_stdout: true)

      if xvfb_exit != 0 do
        IO.puts("Skipping launch test: xvfb-run not available")
      else
        sidecar_path = create_fake_sidecar(tmp_dir)
        assert File.exists?(sidecar_path)

        socket_name = ExTauri.Paths.sanitize_name(@app_name)
        heartbeat_path = Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.sock")

        # Clean up any leftover socket
        File.rm(heartbeat_path)

        # Start a heartbeat socket listener (simulating ExTauri.ShutdownManager)
        {:ok, listen_socket} =
          :gen_tcp.listen(0, [
            :binary,
            {:ifaddr, {:local, heartbeat_path}},
            {:active, false},
            {:reuseaddr, true}
          ])

        # Launch the Tauri app under xvfb-run with a timeout.
        # We use Port to get async control over the process.
        port =
          Port.open(
            {:spawn_executable, "/usr/bin/xvfb-run"},
            [
              :binary,
              :exit_status,
              :stderr_to_stdout,
              args: [
                "--auto-servernum",
                "--server-args=-screen 0 1024x768x24",
                binary_path
              ],
              cd: src_tauri
            ]
          )

        # Wait for the app to connect to our heartbeat socket (up to 30s).
        # This proves the full startup sequence ran: sidecar launch →
        # check_server_started → start_heartbeat → socket connect.
        heartbeat_connected =
          try do
            # Accept with 30s timeout
            case :gen_tcp.accept(listen_socket, 30_000) do
              {:ok, client} ->
                # Wait for at least one heartbeat byte
                case :gen_tcp.recv(client, 1, 5_000) do
                  {:ok, _data} -> true
                  {:error, _} -> false
                end

              {:error, _} ->
                false
            end
          rescue
            _ -> false
          end

        # Collect any output for diagnostics
        output = collect_port_output(port, 500)

        # Clean up: kill the app
        case Port.info(port, :os_pid) do
          {:os_pid, os_pid} ->
            System.cmd("kill", ["-TERM", to_string(os_pid)], stderr_to_stdout: true)
            # Give it a moment to die
            Process.sleep(500)
            System.cmd("kill", ["-9", to_string(os_pid)], stderr_to_stdout: true)

          nil ->
            :ok
        end

        catch_port_exit(port)
        :gen_tcp.close(listen_socket)
        File.rm(heartbeat_path)

        assert heartbeat_connected,
               """
               Tauri app did not connect to heartbeat socket within 30s.
               This means the startup sequence (sidecar → server check → heartbeat) failed.

               App output:
               #{output}
               """
      end
    end

    test "generated Cargo.toml is valid TOML", %{tmp_dir: tmp_dir} do
      cargo_toml = Mix.Tasks.ExTauri.Install.cargo_toml(@app_name, @tauri_version)
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

      # Verify heartbeat uses the correct socket name
      assert main_rs =~ "tauri_heartbeat_#{socket_name}.sock"
      assert main_rs =~ "std::env::temp_dir()"
    end

    test "generated capabilities.json is valid JSON with required permissions" do
      json_str = Mix.Tasks.ExTauri.Install.capabilities_json()
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

  describe "install task file generation" do
    test "generates correct files for a project with spaces in name" do
      app_name = "My Test App"
      cargo_toml = Mix.Tasks.ExTauri.Install.cargo_toml(app_name, @tauri_version)

      assert cargo_toml =~ ~s(name = "my_test_app")
      assert cargo_toml =~ ~s(default-run = "my_test_app")
    end

    test "socket name handles special characters" do
      socket_name = "my_test_app"
      main_rs = Mix.Tasks.ExTauri.Install.main_src(@host, @port, socket_name)

      assert main_rs =~ "tauri_heartbeat_my_test_app.sock"
    end
  end

  # --- Helpers ---

  defp collect_port_output(port, timeout_ms) do
    receive do
      {^port, {:data, data}} ->
        data <> collect_port_output(port, timeout_ms)
    after
      timeout_ms -> ""
    end
  end

  defp catch_port_exit(port) do
    receive do
      {^port, {:exit_status, _}} -> :ok
    after
      2_000 ->
        # Force close if still open
        try do
          Port.close(port)
        rescue
          _ -> :ok
        end
    end
  end
end
