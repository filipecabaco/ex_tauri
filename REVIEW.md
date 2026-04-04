# ExTauri Library Review: Missing Features & Release Readiness

## Current State

ExTauri provides:
- Phoenix-to-Tauri integration via sidecar pattern (Burrito-wrapped BEAM)
- Mix tasks: `install`, `dev`, `build`, `info`, `icon`, `signer`
- Heartbeat-based graceful shutdown via Unix domain sockets
- Window configuration (title, size, fullscreen, resize)
- Tauri plugins: `log` and `shell`

This is essentially **scaffolding + lifecycle management**. The library generates Rust boilerplate and manages the build pipeline, but provides no Elixir-side APIs for desktop-specific functionality.

---

## Missing Features

### 1. Filesystem Utilities

Desktop apps need local filesystem access beyond what Elixir's `File` module provides:

- **App data directories** — No helper for platform-appropriate paths (`~/Library/Application Support/` on macOS, `~/.local/share/` on Linux). The example hardcodes `System.user_home!()`. Tauri has `tauri-plugin-fs` and path resolution APIs that are not wired up.
- **File dialogs** — No open/save file dialog. Tauri has `tauri-plugin-dialog` for native file pickers. Users have no way to let end-users select files from the Elixir side.
- **Drag and drop** — Tauri supports drag-and-drop events but there's no bridge to Phoenix/LiveView.

**Recommendation**: An `ExTauri.Paths` module resolving platform-appropriate directories (`data_dir/0`, `config_dir/0`, `cache_dir/0`, `log_dir/0`) and an `ExTauri.Dialog` module for file open/save via Tauri commands.

### 2. Network Utilities

- **Deep linking / custom URL schemes** — Tauri has `tauri-plugin-deep-link`. Desktop apps commonly need `myapp://` URL handling for OAuth callbacks and inter-app communication.
- **Tauri command/event bridge** — The only communication channel is the WebView loading Phoenix over HTTP. There's no way to send structured messages between Rust and Elixir outside of the heartbeat socket.

**Recommendation**: Document that network operations should use Elixir libraries directly (`:httpc`, Req, Finch). Add deep-link support for OAuth flows.

### 3. Notification Utilities

- **System notifications** — Tauri has `tauri-plugin-notification` for native OS notifications. Currently there's no way to send desktop notifications from Elixir/Phoenix code.
- **System tray** — Tauri V2 supports system tray icons and menus. No integration exists. Important for apps that minimize to tray.

**Recommendation**: `ExTauri.Notification` module for native notifications and `ExTauri.Tray` for system tray management, both via a Tauri command bridge.

### 4. OS-Specific Utilities

- **Clipboard** — Tauri has `tauri-plugin-clipboard-manager`. No integration.
- **Global shortcuts** — Tauri has `tauri-plugin-global-shortcut`. No integration.
- **OS info** — Tauri has `tauri-plugin-os` for platform detection, locale, etc.
- **Single instance** — Tauri has `tauri-plugin-single-instance` to prevent multiple app instances. Important for desktop apps with local databases.
- **Autostart** — Tauri has `tauri-plugin-autostart` for launch-at-login.
- **Window management** — Beyond initial config (width/height/fullscreen), there's no runtime window control (minimize, maximize, set title, open new windows, multi-window).

**Recommendation**: Priority order: single-instance > clipboard > global shortcuts > autostart > OS info.

### 5. Upgradability / Auto-Update

- The `signer` mix task exists for code signing, but **there's no actual updater integration**. Tauri has `tauri-plugin-updater` supporting check/download/apply updates.
- No update server configuration or manifest generation.
- No documentation on how to set up an update workflow (GitHub Releases, S3, custom server).

**Recommendation**: Wire up `tauri-plugin-updater` in the generated Rust code. Add `ExTauri.Updater` config for update endpoint URL and public key. Consider a `mix ex_tauri.release` task that builds + signs + generates update manifests.

---

## Windows Support Analysis

### Assumption: "Windows requires more work due to lack of Burrito support"

**Partially correct, but the blocker is ExTauri's architecture, not Burrito.**

Burrito itself **does** support Windows — it can produce Windows executables. The blockers are:

1. **Unix domain sockets** — The heartbeat mechanism uses `std::os::unix::net::UnixStream` in Rust (`lib/mix/tasks/ex_tauri.install.ex:430`) which **will not compile on Windows**.
2. **Hardcoded `/tmp/` paths** — Socket path `/tmp/tauri_heartbeat_<name>.sock` doesn't exist on Windows.
3. **Elixir ShutdownManager** — Uses `{:ifaddr, {:local, socket_path}}` for Unix domain sockets.
4. **SIGTERM** — The graceful shutdown uses `kill -TERM` which is Unix-only. The Rust side has a `#[cfg(windows)]` fallback that just sleeps 2 seconds — incomplete.

**To support Windows**: Named pipes or TCP localhost sockets, `%APPDATA%` paths, and a Windows-compatible IPC mechanism would all be needed. This is non-trivial and deferring it is the right call.

---

## Architectural Gaps

### No Tauri Command Bridge (Critical)

The biggest gap: **no bidirectional communication between Elixir and Tauri beyond HTTP**.

- Tauri → Phoenix: WebView loads HTTP pages (works)
- Phoenix → Tauri: **Nothing** (no way to invoke Tauri APIs from Elixir)

All missing features (notifications, clipboard, dialogs, etc.) require a **command bridge**. Options:
- Extend the existing heartbeat socket to be bidirectional with JSON commands
- A LiveView JS hook that forwards calls to Tauri's `invoke()` API
- A dedicated WebSocket channel for structured commands

This is the **single most impactful improvement** — it unlocks all plugin integrations.

---

## Other Issues

### Code Quality

| Issue | Location | Details |
|-------|----------|---------|
| Wrong MixProject name | `mix.exs:1` | `Desktop.MixProject` should be `ExTauri.MixProject` |
| Missing `mod:` in application | `mix.exs:17` | `ExTauri` has `use Application` but `mod:` is not set, so `start/2` is never called |
| Hardcoded `/tmp/` | `shutdown_manager.ex:67` | Should use `System.tmp_dir!/0` for portability |
| Hardcoded sidecar name | `ex_tauri.install.ex:170` | `burrito_out/desktop` is not configurable |
| TODO workaround | `ex_tauri.install.ex:157-161` | `build.rs` copy hack with comment "remove this when possible" |

### Testing

- Tests are mostly documentation-style assertions (testing string contents of hardcoded docs)
- No tests for `ShutdownManager` behavior
- No tests for mix tasks
- `BuildReleaseTest` tests literal documentation strings, not actual behavior
- Integration tests call `ExTauri.__test_*` functions that don't appear to be defined

### Infrastructure

- **No CI/CD** — No GitHub Actions or CI configuration
- **No Hex package** — Only available via git dependency
- **No config validation** — Missing `:host`/`:port` only discovered at `mix ex_tauri.install` runtime

### Missing LiveView Integration

Since the primary use case is Phoenix LiveView, there should be:
- A LiveView JS hook for Tauri interop (calling `window.__TAURI__` APIs)
- A JS hook for passing Tauri events to LiveView (window focus/blur, system theme changes)

---

## Recommended Priority for Release

| Priority | Feature | Impact |
|----------|---------|--------|
| **P0** | Tauri Command Bridge (architecture) | Unlocks all plugin integrations |
| **P0** | Fix MixProject naming + `mod:` config | Correctness |
| **P1** | `ExTauri.Paths` — platform app directories | Basic desktop requirement |
| **P1** | Single Instance plugin | Prevents data corruption |
| **P1** | File Dialogs | Basic desktop UX expectation |
| **P1** | System Notifications | Basic desktop UX expectation |
| **P2** | Auto-Updater integration | Critical for distribution |
| **P2** | System Tray | Expected for long-running desktop apps |
| **P2** | LiveView JS hooks for Tauri interop | Developer experience |
| **P3** | CI/CD pipeline | Project maintenance |
| **P3** | Publish to Hex | Adoption |
| **P3** | Config validation at compile time | Developer experience |
| **P3** | Replace hardcoded `/tmp/` with `System.tmp_dir!/0` | Portability |
| **Deferred** | Windows support | Requires architectural changes to IPC |
