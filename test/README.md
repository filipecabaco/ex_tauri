# ExTauri Tests

This directory contains integration tests for the ExTauri library to verify that the generated Tauri V2 code is correct.

## Running Tests

To run all tests:

```bash
mix test
```

To run only integration tests:

```bash
mix test --only integration
```

To run with verbose output:

```bash
mix test --trace
```

## Test Coverage

### `ex_tauri_test.exs`
Basic unit tests for public API functions:
- `latest_version/0` - Verifies the default Tauri version
- `installation_path/0` - Verifies the installation path structure

### `ex_tauri_integration_test.exs`
Comprehensive integration tests for code generation:

#### Cargo.toml Generation Tests
- Verifies V2 dependencies (tauri-plugin-shell, tauri-plugin-log)
- Ensures Rust edition 2021 is used (not 2018)
- Validates package configuration
- Confirms NO V1 features like "api-all"
- **Critical**: Verifies semver ranges are used for all Tauri components:
  - Plugins: `tauri-plugin-shell = "2"` (not `"2.5.1"`)
  - Core: `tauri = { version = "2", features = [] }`
  - Build: `tauri-build = { version = "2", features = [] }`
  - CLI installation: `cargo install tauri-cli --version ^2` (not exact version)
- Tests version extraction across different version formats (stable, pre-release)
- Ensures independent versioning to avoid Cargo build failures

#### main.rs Generation Tests
- Verifies V2 plugin system initialization
- Validates new ShellExt trait usage
- Ensures sidecar spawning uses new V2 API
- Confirms CommandEvent::Stdout handles bytes (not strings)
- Validates async runtime usage
- Tests server startup check logic

#### capabilities.json Generation Tests
- Verifies valid V2 ACL structure
- Validates JSON schema reference
- Ensures shell permissions (allow-execute, allow-spawn)
- Confirms desktop sidecar is explicitly allowed
- Validates JSON is well-formed

#### V2 Compatibility Verification
- Confirms NO V1 API patterns exist in generated code
- Validates all V2-specific patterns are present
- Ensures configuration uses V2 structure (not V1 allowlist)

#### CLI Installation Command Generation Tests
- **Critical**: Validates `mix ex_tauri.install` won't fail with version errors
- Tests major version extraction from configured Tauri version
- Verifies cargo install command uses caret semver range (`^2`)
- Ensures exact versions are NOT used (prevents "version not found" errors)
- Tests command structure matches cargo expectations
- Validates handling of edge cases (pre-release, build metadata, etc.)
- Tests fallback behavior for invalid version strings
- Prevents regression of the `tauri-cli@2.5.1` installation bug

## What These Tests Verify

The integration tests ensure that ExTauri generates code compatible with **Tauri V2 only**:

### ✅ V2 Features Present
- Rust edition 2021
- `tauri-plugin-shell` dependency with semver major version (e.g., "2")
- `tauri-plugin-log` dependency with semver major version (e.g., "2")
- Semver ranges for all Tauri dependencies to avoid version mismatch errors
- `.plugin()` initialization calls
- `ShellExt` trait usage
- `app.shell().sidecar()` API
- ACL capabilities system
- V2 configuration structure (top-level productName, etc.)
- `features = []` for tauri and tauri-build dependencies

### ❌ V1 Features Removed
- No Rust edition 2018
- No `"api-all"` feature flag
- No `use tauri::api::process`
- No `Command::new_sidecar`
- No allowlist configuration
- No V1 config paths (["tauri", "windows"], etc.)
- No V1 CLI arguments (--dev-path, --dist-dir)

## Test Environment Setup

The library includes test-only functions (prefixed with `__test_`) that expose private code generation functions for testing purposes. These functions are only compiled when `Mix.env() == :test`.

## Manual Testing

While the integration tests validate command generation, you should also manually test the actual installation process:

### Testing CLI Installation

```bash
# 1. Configure your app
config :ex_tauri, version: "2.5.1", app_name: "Test App", host: "localhost", port: 4000

# 2. Run installation
mix ex_tauri.install

# 3. Verify successful installation
# You should see output like:
#   Installing tauri-cli v2.x.x
#   Installed package `tauri-cli v2.x.x` (executable `cargo-tauri`)

# 4. Check the installed version
./_build/_tauri/bin/cargo-tauri --version
```

### What to Look For

✅ **Success indicators:**
- CLI installs without "version not found" errors
- Installation completes with "Installed package" message
- `cargo-tauri` binary exists in `_build/_tauri/bin/`
- Generated Cargo.toml uses semver ranges (e.g., `tauri-plugin-shell = "2"`)

❌ **Failure indicators:**
- Error: `could not find tauri-cli in registry with version =2.5.1`
- Error: `could not find tauri-plugin-shell in registry with version =2.5.1`
- Generated Cargo.toml has exact versions (e.g., `"2.5.1"`)

### Testing Generated Code Compilation

```bash
# After installation, test that generated code builds
cd example/src-tauri
cargo check

# Should complete without version errors
# Any dependency resolution errors indicate a version mismatch bug
```

## Continuous Integration

These tests should be run as part of CI/CD pipelines to ensure:
1. No accidental reintroduction of V1 compatibility
2. Generated code remains compatible with latest Tauri V2
3. All required V2 dependencies are included
4. Configuration structure matches V2 requirements
5. Plugin versions use semver ranges to prevent build failures from version mismatches
6. CLI installation command generation prevents exact version errors
