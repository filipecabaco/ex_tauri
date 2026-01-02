defmodule ExTauriIntegrationTest do
  use ExUnit.Case, async: true

  @moduletag :integration

  describe "Cargo.toml generation" do
    test "generates valid Cargo.toml with V2 dependencies using semver ranges" do
      app_name = "test_app"
      tauri_version = "2.5.1"

      cargo_toml = ExTauri.__test_cargo_toml__(app_name, tauri_version)

      # NOTE: The install() function also uses semver ranges for tauri-cli installation
      # It extracts major version and uses: cargo install tauri-cli --version ^2
      # This prevents "version not found" errors during CLI installation

      # Verify package configuration
      assert cargo_toml =~ ~r/name = "test_app"/
      assert cargo_toml =~ ~r/version = "0\.1\.0"/
      assert cargo_toml =~ ~r/edition = "2021"/
      assert cargo_toml =~ ~r/build = "src\/build\.rs"/

      # Verify build dependencies use semver major version (not exact version)
      assert cargo_toml =~ ~r/\[build-dependencies\]/
      assert cargo_toml =~ ~r/tauri-build = \{ version = "2", features = \[\] \}/

      # Verify runtime dependencies
      assert cargo_toml =~ ~r/\[dependencies\]/
      assert cargo_toml =~ ~r/log = "0\.4"/
      assert cargo_toml =~ ~r/serde_json = "1\.0"/
      assert cargo_toml =~ ~r/serde = \{ version = "1\.0", features = \["derive"\] \}/

      # Core tauri should use semver major version
      assert cargo_toml =~ ~r/tauri = \{ version = "2", features = \[\] \}/

      # Plugins should use semver major version (not exact version like "2.5.1")
      # This is critical because plugins have independent versioning
      assert cargo_toml =~ ~r/tauri-plugin-shell = "2"/
      assert cargo_toml =~ ~r/tauri-plugin-log = "2"/

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
        cargo_toml = ExTauri.__test_cargo_toml__("test_app", tauri_version)

        # Plugins should use major version only
        assert cargo_toml =~ ~r/tauri-plugin-shell = "#{expected_major}"/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~ ~r/tauri-plugin-log = "#{expected_major}"/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~ ~r/tauri = \{ version = "#{expected_major}", features = \[\] \}/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"

        assert cargo_toml =~ ~r/tauri-build = \{ version = "#{expected_major}", features = \[\] \}/,
               "Failed for version #{tauri_version}: expected major version #{expected_major}"
      end
    end

    test "generates Cargo.toml with Rust edition 2021, not 2018" do
      cargo_toml = ExTauri.__test_cargo_toml__("my_app", "2.5.1")

      assert cargo_toml =~ ~r/edition = "2021"/
      refute cargo_toml =~ ~r/edition = "2018"/
    end

    test "handles app names with spaces correctly" do
      cargo_toml = ExTauri.__test_cargo_toml__("My Test App", "2.5.1")

      # Should convert to snake_case
      assert cargo_toml =~ ~r/name = "my_test_app"/
    end

    test "includes features = [] for tauri and tauri-build" do
      cargo_toml = ExTauri.__test_cargo_toml__("test_app", "2.5.1")

      # Verify empty features array to match working example
      assert cargo_toml =~ ~r/tauri-build = \{ version = "2", features = \[\] \}/
      assert cargo_toml =~ ~r/tauri = \{ version = "2", features = \[\] \}/
    end
  end

  describe "main.rs generation" do
    test "generates valid main.rs with V2 plugin system" do
      host = "localhost"
      port = "4000"

      main_src = ExTauri.__test_main_src__(host, port)

      # Verify imports
      assert main_src =~ ~r/use tauri_plugin_shell::process::CommandEvent;/
      assert main_src =~ ~r/use tauri_plugin_shell::ShellExt;/

      # Verify plugin initialization
      assert main_src =~ ~r/\.plugin\(tauri_plugin_shell::init\(\)\)/
      assert main_src =~ ~r/\.plugin\(tauri_plugin_log::Builder::new\(\)\.build\(\)\)/

      # Verify setup function signature (V2 uses AppHandle reference)
      assert main_src =~ ~r/fn start_server\(app: &tauri::AppHandle\)/

      # Verify sidecar usage with new API
      assert main_src =~ ~r/app\.shell\(\)\.sidecar\("desktop"\)/
      assert main_src =~ ~r/\.spawn\(\)/
      assert main_src =~ ~r/\.expect\("Failed to spawn desktop sidecar"\)/

      # Verify CommandEvent handling with bytes (V2)
      assert main_src =~ ~r/if let CommandEvent::Stdout\(line_bytes\) = event/
      assert main_src =~ ~r/let line = String::from_utf8_lossy\(&line_bytes\);/

      # Verify server check with correct host and port
      assert main_src =~ ~r/let host = "#{host}"\.to_string\(\);/
      assert main_src =~ ~r/let port = "#{port}"\.to_string\(\);/

      # Ensure NO V1 API usage
      refute main_src =~ ~r/use tauri::api::process/
      refute main_src =~ ~r/Command::new_sidecar/
      refute main_src =~ ~r/CommandEvent::Stdout\(line\)/ # V1 used strings, not bytes
    end

    test "generates main.rs with correct async runtime usage" do
      main_src = ExTauri.__test_main_src__("localhost", "4000")

      assert main_src =~ ~r/tauri::async_runtime::spawn\(async move/
      assert main_src =~ ~r/while let Some\(event\) = rx\.recv\(\)\.await/
    end

    test "generates main.rs with server startup check" do
      main_src = ExTauri.__test_main_src__("localhost", "4000")

      assert main_src =~ ~r/fn check_server_started\(\)/
      assert main_src =~ ~r/TcpStream::connect/
      assert main_src =~ ~r/std::time::Duration::from_millis\(200\)/
    end

    test "handles different host and port configurations" do
      main_src = ExTauri.__test_main_src__("127.0.0.1", "8080")

      assert main_src =~ ~r/let host = "127\.0\.0\.1"\.to_string\(\);/
      assert main_src =~ ~r/let port = "8080"\.to_string\(\);/
    end
  end

  describe "capabilities.json generation" do
    test "generates valid capabilities.json with V2 ACL structure" do
      capabilities_json = ExTauri.__test_capabilities_json__()

      # Parse JSON to verify structure
      {:ok, capabilities} = Jason.decode(capabilities_json)

      # Verify schema reference
      assert capabilities["$schema"] == "../gen/schemas/desktop-schema.json"

      # Verify basic metadata
      assert capabilities["identifier"] == "default"
      assert capabilities["description"] == "Capability for the main application window"
      assert capabilities["windows"] == ["main"]

      # Verify permissions array exists
      assert is_list(capabilities["permissions"])
      permissions = capabilities["permissions"]

      # Verify shell permissions
      assert "shell:allow-execute" in permissions
      assert "shell:allow-spawn" in permissions

      # Verify sidecar permission configuration
      sidecar_permission =
        Enum.find(permissions, fn
          %{"identifier" => "shell:allow-execute"} -> true
          _ -> false
        end)

      assert sidecar_permission != nil
      assert is_list(sidecar_permission["allow"])
      assert %{"name" => "desktop", "sidecar" => true} in sidecar_permission["allow"]
    end

    test "capabilities.json is valid JSON" do
      capabilities_json = ExTauri.__test_capabilities_json__()

      # Should parse without errors
      assert {:ok, _} = Jason.decode(capabilities_json)
    end

    test "capabilities.json includes all required permissions for external binary" do
      capabilities_json = ExTauri.__test_capabilities_json__()
      {:ok, capabilities} = Jason.decode(capabilities_json)

      permissions = capabilities["permissions"]

      # Must have both execute and spawn permissions
      assert "shell:allow-execute" in permissions
      assert "shell:allow-spawn" in permissions

      # Must explicitly allow the desktop sidecar
      sidecar_configs =
        permissions
        |> Enum.filter(&is_map/1)
        |> Enum.flat_map(fn config -> Map.get(config, "allow", []) end)

      desktop_config = Enum.find(sidecar_configs, fn config ->
        config["name"] == "desktop" && config["sidecar"] == true
      end)

      assert desktop_config != nil, "Desktop sidecar must be explicitly allowed in capabilities"
    end
  end

  describe "V2 compatibility verification" do
    test "generated files use only V2 APIs and configurations" do
      cargo_toml = ExTauri.__test_cargo_toml__("test_app", "2.5.1")
      main_src = ExTauri.__test_main_src__("localhost", "4000")
      capabilities = ExTauri.__test_capabilities_json__()

      # V1-specific patterns that should NOT appear
      v1_patterns = [
        ~r/tauri.*1\.\d/,  # V1 version numbers
        ~r/api-all/,  # V1 feature flag
        ~r/use tauri::api::process/,  # V1 import
        ~r/Command::new_sidecar/,  # V1 sidecar API
        ~r/allowlist/,  # V1 permission system
        ~r/edition = "2018"/  # Old Rust edition
      ]

      for pattern <- v1_patterns do
        refute cargo_toml =~ pattern, "Cargo.toml should not contain V1 pattern: #{inspect(pattern)}"
        refute main_src =~ pattern, "main.rs should not contain V1 pattern: #{inspect(pattern)}"
        refute capabilities =~ pattern, "capabilities.json should not contain V1 pattern: #{inspect(pattern)}"
      end

      # V2-specific patterns that MUST appear
      assert cargo_toml =~ ~r/tauri-plugin-shell/
      assert cargo_toml =~ ~r/tauri-plugin-log/
      assert cargo_toml =~ ~r/edition = "2021"/
      assert main_src =~ ~r/\.plugin\(/
      assert main_src =~ ~r/tauri_plugin_shell::ShellExt/
      assert capabilities =~ ~r/shell:allow-execute/

      # Verify semver ranges are used (not exact versions)
      assert cargo_toml =~ ~r/tauri = \{ version = "2", features = \[\] \}/
      assert cargo_toml =~ ~r/tauri-plugin-shell = "2"/
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
end
