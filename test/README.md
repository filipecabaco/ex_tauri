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

## What These Tests Verify

The integration tests ensure that ExTauri generates code compatible with **Tauri V2 only**:

### ✅ V2 Features Present
- Rust edition 2021
- `tauri-plugin-shell` dependency
- `tauri-plugin-log` dependency
- `.plugin()` initialization calls
- `ShellExt` trait usage
- `app.shell().sidecar()` API
- ACL capabilities system
- V2 configuration structure (top-level productName, etc.)

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

## Continuous Integration

These tests should be run as part of CI/CD pipelines to ensure:
1. No accidental reintroduction of V1 compatibility
2. Generated code remains compatible with latest Tauri V2
3. All required V2 dependencies are included
4. Configuration structure matches V2 requirements
