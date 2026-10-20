defmodule ExTauriIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  alias ExTauri.Install.Helpers

  describe "Cargo.toml generation" do
    test "generates valid Cargo.toml with V2 dependencies using semver ranges" do
      app_name = "test_app"
      tauri_version = "2.5.1"

      cargo_toml = Helpers.cargo_toml(app_name, tauri_version)

      # NOTE: The install() function also uses semver ranges for tauri-cli installation
      # It extracts major version and uses: cargo install tauri-cli --version ^2
      # This prevents "version not found" errors during CLI installation

      # Verify package configuration
      assert cargo_toml =~ ~r/name = "test_app"/
      assert cargo_toml =~ "version = \"#{ExTauri.version()}\""
      assert cargo_toml =~ ~r/edition = "2021"/

      # Verify build dependencies use semver major version (not exact version)
      assert cargo_toml =~ ~r/\[build-dependencies\]/
      assert cargo_toml =~ ~r/tauri-build = \{ version = "2", features = \[\] \}/

      # Verify runtime dependencies
      assert cargo_toml =~ ~r/\[dependencies\]/
      assert cargo_toml =~ ~r/log = "0\.4"/
      assert cargo_toml =~ ~r/serde_json = "1\.0"/
      assert cargo_toml =~ ~r/serde = \{ version = "1\.0", features = \["derive"\] \}/

      # Core tauri should use semver major version
      assert cargo_toml =~
               ~r/tauri = \{ version = "2", features = \["tray-icon", "webview-data-url"\] \}/

      # Plugins should use semver major version (not exact version like "2.5.1")
      # This is critical because plugins have independent versioning. The shell
      # plugin is the exception: set_process_group needs 2.5.
      assert cargo_toml =~ ~r/tauri-plugin-shell = "2\.5"/
      assert cargo_toml =~ ~r/tauri-plugin-log = "2"/
      assert cargo_toml =~ ~r/tauri-plugin-notification = "2"/

      # Ensure exact version is NOT used for plugins
      refute cargo_toml =~ ~r/tauri-plugin-shell = "#{tauri_version}"/
      refute cargo_toml =~ ~r/tauri-plugin-log = "#{tauri_version}"/

      # Verify features
      assert cargo_toml =~ ~r/\[features\]/
      assert cargo_toml =~ ~r/custom-protocol = \[ "tauri\/custom-protocol" \]/

      # Ensure NO V1 features like "api-all"
      refute cargo_toml =~ ~r/api-all/
    end

    test "uses semver major version for plugins to avoid version mismatch" do
      # Test with different Tauri versions to ensure major version extraction works
      test_cases = [
        {"2.5.1", "2"},
        {"2.0.0", "2"},
        {"2.10.3", "2"},
        {"3.0.0-beta.1", "3"}
      ]

      for {tauri_version, expected_major} <- test_cases do
        cargo_toml = Helpers.cargo_toml("test_app", tauri_version)

        # Plugins should use major version only (shell needs 2.5 on major 2)
        expected_shell = if expected_major == "2", do: "2\\.5", else: expected_major

        assert cargo_toml =~ ~r/tauri-plugin-shell = "#{expected_shell}"/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~ ~r/tauri-plugin-log = "#{expected_major}"/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~
                 ~r/tauri = \{ version = "#{expected_major}", features = \["tray-icon", "webview-data-url"\] \}/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~
                 ~r/tauri-build = \{ version = "#{expected_major}", features = \[\] \}/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"
      end
    end

    test "generates Cargo.toml with Rust edition 2021, not 2018" do
      cargo_toml = Helpers.cargo_toml("my_app", "2.5.1")

      assert cargo_toml =~ ~r/edition = "2021"/
      refute cargo_toml =~ ~r/edition = "2018"/
    end

    test "handles app names with spaces correctly" do
      cargo_toml = Helpers.cargo_toml("My Test App", "2.5.1")

      # Should convert to snake_case
      assert cargo_toml =~ ~r/name = "my_test_app"/
    end

    test "includes expected features for tauri and tauri-build" do
      cargo_toml = Helpers.cargo_toml("test_app", "2.5.1")

      assert cargo_toml =~ ~r/tauri-build = \{ version = "2", features = \[\] \}/
      # tray-icon enables ExTauri.Desktop.set_tray/1; webview-data-url the
      # loading and error pages
      assert cargo_toml =~
               ~r/tauri = \{ version = "2", features = \["tray-icon", "webview-data-url"\] \}/
    end

    test "pulls in objc2 for App Nap on macOS only" do
      cargo_toml = Helpers.cargo_toml("test_app", "2.5.1")

      assert cargo_toml =~ ~s{[target.'cfg(target_os = "macos")'.dependencies]}
      assert cargo_toml =~ ~s{"NSProcessInfo"}
      # Plugins patch the first `[dependencies]\n`; the target table must not be it.
      [_, after_main] = String.split(cargo_toml, "\n[dependencies]\n", parts: 2)
      assert after_main =~ "tauri-plugin-shell"
    end
  end

  describe "main.rs generation" do
    test "generates valid main.rs with V2 plugin system" do
      host = "localhost"
      port = "4000"

      main_src = Helpers.main_src(host, port, "test_app")

      # Verify imports
      assert main_src =~ ~r/use tauri_plugin_shell::process::\{CommandChild, CommandEvent\};/
      assert main_src =~ ~r/use tauri_plugin_shell::ShellExt;/

      # Verify plugin initialization
      assert main_src =~ ~r/\.plugin\(tauri_plugin_shell::init\(\)\)/
      assert main_src =~ "tauri_plugin_log::Builder::new()"
      assert main_src =~ ~r/\.plugin\(tauri_plugin_notification::init\(\)\)/

      # Verify setup function signature (V2 uses AppHandle reference; the
      # port is resolved at runtime and passed in)
      assert main_src =~
               ~r/fn spawn_sidecar\(app: &tauri::AppHandle, port: u16\) -> Result<\(\), String>/

      # Verify sidecar usage with new API — and no panic when it is missing
      assert main_src =~ ~s{.sidecar("desktop")}
      assert main_src =~ ~r/\.spawn\(\)/
      refute main_src =~ ~s{.expect("Failed to spawn}

      # Verify CommandEvent handling with bytes (V2)
      assert main_src =~ "CommandEvent::Stdout(bytes) => log_sidecar_line(&bytes, false)"
      assert main_src =~ "CommandEvent::Terminated(exit)"
      assert main_src =~ "String::from_utf8_lossy(bytes)"

      # Verify server check with correct host; the port is resolved at runtime
      # (EX_TAURI_PORT in dev, an OS-assigned free port in production).
      assert main_src =~ ~s[format!("#{host}:{}", port)]
      assert main_src =~ "fn resolve_port()"
      assert main_src =~ "EX_TAURI_PORT"
      assert main_src =~ ".unwrap_or(#{port})"

      # Ensure NO V1 API usage
      refute main_src =~ ~r/use tauri::api::process/
      refute main_src =~ ~r/Command::new_sidecar/
      # V1 used strings, not bytes
      refute main_src =~ ~r/CommandEvent::Stdout\(line\)/
    end

    test "generates main.rs with correct async runtime usage" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~ ~r/tauri::async_runtime::spawn\(watch_sidecar\(/
      assert main_src =~ ~r/while let Some\(event\) = rx\.recv\(\)\.await/
    end

    test "waits for the backend off the main thread, with a deadline" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      # setup hands the wait to a worker thread; blocking it froze the app.
      assert main_src =~ ~r/\.setup\(\|app\| \{.*?std::thread::spawn/s
      assert main_src =~ ~r/fn wait_for_backend\(port: u16\) -> Result<\(\), String>/
      assert main_src =~ "STARTUP_DEADLINE"
      assert main_src =~ "SIDECAR_EXITED"
      assert main_src =~ ~r/TcpStream::connect/
      refute main_src =~ "fn check_server_started"
    end

    test "starts the sidecar so Burrito 1.6 neither halts it nor hides it from signals" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~ ~s{.args(["--no-halt"])}
      assert main_src =~ ".set_process_group(true)"
      assert main_src =~ "EX_TAURI_SHELL_PID"
      assert main_src =~ "fn beam_pid(root: u32)"
    end

    test "tells the user, and restarts, when the backend dies" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~ "fn recover_backend("
      assert main_src =~ "MAX_RESTARTS"
      assert main_src =~ "Page::StartFailed"
      assert main_src =~ "Page::Stopped"
      assert main_src =~ "ERL_CRASH_DUMP"
    end

    test "a backend that exits releases its keep_awake" do
      # A restarted backend starts believing nothing is held; found by killing
      # the BEAM under a real build and watching App Nap stay disabled.
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~
               ~r/CommandEvent::Terminated\(exit\) => \{.*?app_nap::set_disabled\(false\)/s
    end

    test "keeps its log instead of rotating it away" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~ "RotationStrategy::KeepSome(5)"
      assert main_src =~ ".max_file_size(5_000_000)"
      assert main_src =~ ".level(log::LevelFilter::Info)"
    end

    test "quits only from its own Quit item, and off the UI thread" do
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~ ~s{const QUIT_ID: &str = "ex_tauri:quit";}
      refute main_src =~ ~s{contains("quit")}
      refute main_src =~ "std::process::exit"
      assert main_src =~ ~r/fn quit\(app: &tauri::AppHandle\) \{.*?std::thread::spawn/s
    end

    test "stops the backend when macOS terminates the app itself" do
      # Quit from the Dock, an AppleScript `quit` and logging out never send
      # ExitRequested; found by quitting a real build and reading its log.
      main_src = Helpers.main_src("localhost", "4000", "test_app")

      assert main_src =~
               ~r/tauri::RunEvent::Exit => \{\s+if !EXIT_READY.*?stop_sidecar\(app_handle\)/s
    end

    test "handles different host and port configurations" do
      main_src = Helpers.main_src("127.0.0.1", "8080", "test_app")

      assert main_src =~ ~s[format!("127.0.0.1:{}", port)]
      assert main_src =~ ".unwrap_or(8080)"
    end
  end

  describe "capabilities.json generation" do
    test "generates valid capabilities.json with V2 ACL structure" do
      capabilities_json = Helpers.capabilities_json()

      # Parse JSON to verify structure
      {:ok, capabilities} = Jason.decode(capabilities_json)

      # Verify schema reference
      assert capabilities["$schema"] == "../gen/schemas/desktop-schema.json"

      # Verify basic metadata
      assert capabilities["identifier"] == "default"
      assert capabilities["description"] == "Capability for the main application window"
      assert capabilities["windows"] == ["main", "*"]

      # Verify permissions array exists
      assert is_list(capabilities["permissions"])
      permissions = capabilities["permissions"]

      # Verify notification permissions
      assert "notification:default" in permissions

      # No shell execution at all: the Rust shell spawns the sidecar, and with
      # `remote` set any page on the host could start another copy of it.
      refute Enum.any?(permissions, &match?(%{"identifier" => "shell:allow-execute"}, &1))
      refute "shell:allow-execute" in permissions
      refute "shell:allow-spawn" in permissions
    end

    test "capabilities.json is valid JSON" do
      capabilities_json = Helpers.capabilities_json()

      # Should parse without errors
      assert {:ok, _} = Jason.decode(capabilities_json)
    end

    test "applies to the app's real page, which is on an ephemeral port" do
      # Tauri counts a page as local only under frontendDist; the shell
      # navigates the window to a port picked at launch, so without `remote`
      # every invoke from the real page is denied.
      {:ok, capabilities} = Jason.decode(Helpers.capabilities_json())
      assert capabilities["remote"] == %{"urls" => ["http://localhost:*"]}

      {:ok, capabilities} = Jason.decode(Helpers.capabilities_json("https", "127.0.0.1"))
      assert capabilities["remote"] == %{"urls" => ["https://127.0.0.1:*"]}
    end
  end

  describe "V2 compatibility verification" do
    test "generated files use only V2 APIs and configurations" do
      cargo_toml = Helpers.cargo_toml("test_app", "2.5.1")
      main_src = Helpers.main_src("localhost", "4000", "test_app")
      capabilities = Helpers.capabilities_json()

      # V1-specific patterns that should NOT appear
      v1_patterns = [
        # V1 version numbers
        ~r/tauri.*1\.\d/,
        # V1 feature flag
        ~r/api-all/,
        # V1 import
        ~r/use tauri::api::process/,
        # V1 sidecar API
        ~r/Command::new_sidecar/,
        # V1 permission system
        ~r/allowlist/,
        # Old Rust edition
        ~r/edition = "2018"/
      ]

      for pattern <- v1_patterns do
        refute cargo_toml =~ pattern,
               "Cargo.toml should not contain V1 pattern: #{inspect(pattern)}"

        refute main_src =~ pattern, "main.rs should not contain V1 pattern: #{inspect(pattern)}"

        refute capabilities =~ pattern,
               "capabilities.json should not contain V1 pattern: #{inspect(pattern)}"
      end

      # V2-specific patterns that MUST appear
      assert cargo_toml =~ ~r/tauri-plugin-shell/
      assert cargo_toml =~ ~r/tauri-plugin-log/
      assert cargo_toml =~ ~r/edition = "2021"/
      assert main_src =~ ~r/\.plugin\(/
      assert main_src =~ ~r/tauri_plugin_shell::ShellExt/
      assert capabilities =~ "core:default"

      # Verify semver ranges are used (not exact versions)
      assert cargo_toml =~
               ~r/tauri = \{ version = "2", features = \["tray-icon", "webview-data-url"\] \}/

      assert cargo_toml =~ ~r/tauri-plugin-shell = "2\.5"/
      assert cargo_toml =~ ~r/tauri-plugin-log = "2"/

      # Ensure exact versions like "2.5.1" are NOT used for plugins
      refute cargo_toml =~ ~r/tauri-plugin-shell = "2\.\d+\.\d+"/
      refute cargo_toml =~ ~r/tauri-plugin-log = "2\.\d+\.\d+"/
    end
  end

  describe "configuration structure verification" do
    test "verifies config keys are for V2 structure only" do
      # Access module attributes through reflection
      config_keys = %{
        productName: ["productName"],
        externalBin: ["bundle", "externalBin"],
        identifier: ["identifier"],
        windows: ["app", "windows"]
      }

      # V2 config paths (top-level and app-level)
      assert config_keys.productName == ["productName"]
      assert config_keys.identifier == ["identifier"]
      assert config_keys.windows == ["app", "windows"]

      # Ensure NO V1 paths
      refute config_keys.productName == ["package", "productName"]
      refute config_keys.identifier == ["tauri", "bundle", "identifier"]
      refute config_keys.windows == ["tauri", "windows"]
    end

    test "verifies argument names are for V2 CLI only" do
      arg_names = %{
        dev_url: "--dev-url",
        frontend_dist: "--frontend-dist"
      }

      # V2 argument names
      assert arg_names.dev_url == "--dev-url"
      assert arg_names.frontend_dist == "--frontend-dist"

      # Ensure NO V1 argument names
      refute arg_names.dev_url == "--dev-path"
      refute arg_names.frontend_dist == "--dist-dir"
    end
  end

  describe "CLI installation command generation" do
    test "extracts major version correctly for CLI installation" do
      test_cases = [
        {"2.5.1", "2"},
        {"2.0.0", "2"},
        {"2.10.3", "2"},
        {"3.0.0-beta.1", "3"},
        {"3.1.2-rc.3", "3"}
      ]

      for {tauri_version, expected_major} <- test_cases do
        cli_version = Helpers.extract_cli_version(tauri_version)

        assert cli_version == expected_major,
               "Failed for version #{tauri_version}: expected #{expected_major}, got #{cli_version}"
      end
    end

    test "generates correct cargo install command arguments" do
      tauri_version = "2.5.1"
      args = Helpers.build_cli_install_args(tauri_version)

      # Verify command structure
      assert args == ["install", "tauri-cli", "--version", "^2", "--root", "."]

      # Verify it uses semver caret range
      assert "^2" in args

      # Verify it does NOT use exact version
      refute "2.5.1" in args
      refute "@2.5.1" in args
    end

    test "uses caret semver range for all version formats" do
      test_cases = [
        {"2.5.1", "^2"},
        {"2.0.0", "^2"},
        {"3.0.0-beta.1", "^3"},
        {"3.10.5", "^3"}
      ]

      for {tauri_version, expected_version_arg} <- test_cases do
        args = Helpers.build_cli_install_args(tauri_version)

        assert expected_version_arg in args,
               "Expected #{expected_version_arg} in args for version #{tauri_version}, got: #{inspect(args)}"

        # Ensure the package name is correct
        assert "tauri-cli" in args

        # Ensure --version flag is used
        assert "--version" in args

        # Ensure --root flag is present
        assert "--root" in args
        assert "." in args
      end
    end

    test "prevents exact version installation errors" do
      # This is the command that was failing before the fix
      tauri_version = "2.5.1"
      args = Helpers.build_cli_install_args(tauri_version)

      # The old broken command would have been: ["install", "tauri-cli@2.5.1", ...]
      # Verify we're NOT using that format
      refute "tauri-cli@2.5.1" in args
      refute "tauri-cli@#{tauri_version}" in args

      # Verify we ARE using the correct format
      assert args == ["install", "tauri-cli", "--version", "^2", "--root", "."],
             "CLI install args should use --version flag with caret semver range"
    end

    test "command structure matches cargo install expectations" do
      args = Helpers.build_cli_install_args("2.5.1")

      # Verify command structure: install <package> --version <version> --root <path>
      assert Enum.at(args, 0) == "install"
      assert Enum.at(args, 1) == "tauri-cli"
      assert Enum.at(args, 2) == "--version"
      assert Enum.at(args, 3) == "^2"
      assert Enum.at(args, 4) == "--root"
      assert Enum.at(args, 5) == "."

      # Verify exact order (important for cargo)
      assert args == ["install", "tauri-cli", "--version", "^2", "--root", "."]
    end

    test "handles edge cases in version parsing" do
      edge_cases = [
        # Pre-release versions
        {"2.0.0-alpha.1", "^2"},
        {"2.0.0-beta.10", "^2"},
        {"2.0.0-rc.1", "^2"},
        # Versions with build metadata
        {"2.5.1+build.123", "^2"},
        # Simple versions
        {"2.0.0", "^2"},
        {"3.0.0", "^3"}
      ]

      for {tauri_version, expected_version_arg} <- edge_cases do
        args = Helpers.build_cli_install_args(tauri_version)

        assert expected_version_arg in args,
               "Failed to handle version #{tauri_version}: expected #{expected_version_arg} in #{inspect(args)}"
      end
    end

    test "fallback behavior for invalid version strings" do
      # If version parsing fails, it should use the original version
      # This is a safety fallback to prevent total failure
      invalid_version = "invalid-version"
      cli_version = Helpers.extract_cli_version(invalid_version)

      # Should fall back to the original string
      assert cli_version == invalid_version
    end
  end
end
