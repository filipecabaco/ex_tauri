# ExTauri Library Review: Current State & Remaining Work

## Current State

ExTauri provides:
- Phoenix-to-Tauri integration via sidecar pattern (Burrito-wrapped BEAM)
- Mix tasks: `install`, `dev`, `build`, `info`, `icon`, `signer`
- Heartbeat-based graceful shutdown via Unix domain sockets
- Window configuration (title, size, fullscreen, resize)
- LiveView JS hook bridge for Tauri API access
- Elixir API modules: Notification, Shell, Dialog, Clipboard, Filesystem, OS
- Platform-appropriate path resolution (macOS, Linux, Windows)
- Updater configuration and signing support
- Proper OTP supervision tree with Task.Supervisor

## Resolved Issues

The following issues from prior reviews have been addressed:

| Issue | Resolution |
|-------|------------|
| No Tauri Command Bridge | LiveView JS hook (`TauriHook`) bridges all Tauri plugin APIs |
| No `ExTauri.Paths` module | Added with macOS, Linux, and Windows support + XDG compliance |
| No file dialogs | `ExTauri.Dialog` module with open/save/message/confirm/ask |
| No system notifications | `ExTauri.Notification` module |
| No clipboard support | `ExTauri.Clipboard` module |
| No filesystem access | `ExTauri.Filesystem` module |
| No OS info | `ExTauri.OS` module |
| Wrong MixProject name | Fixed to `ExTauri.MixProject` |
| Missing `mod:` in application | Fixed — `ExTauri` implements `Application` with proper supervisor |
| Hardcoded `/tmp/` | Uses `System.tmp_dir!/0` |
| Empty supervisor | Now supervises `ExTauri.TaskSupervisor` for socket accept tasks |
| macOS-only Burrito cache nuke | Removed — Burrito handles its own cache |
| `build.rs` copy hack | Removed — Cargo.toml now uses the default `build.rs` location |
| Inline Rust template | Moved to `priv/templates/main.rs.eex` |
| Updater not wired into build | `ExTauri.Updater.tauri_config/0` merged into `tauri.conf.json` |
| No plugin setup docs | Each API module documents Cargo.toml, main.rs, and capabilities setup |
| No ref-based response correlation | `ExTauri.Hook.push_command_tracked/4` for concurrent command disambiguation |
| No migration guidance | README documents release migration pattern for Ecto apps |
| No Windows paths | `ExTauri.Paths` handles `%APPDATA%` and `%LOCALAPPDATA%` |
| Dev mode uses full Burrito build | `run_dev/1` builds standard release with shell wrapper sidecar |
| TauriHook fragile on re-render | Added `reconnected()`, `destroyed()` lifecycle callbacks |
| OTP version constraint hidden | `validate_config` and `preflight_check!` surface clear OTP warnings |
| Windows heartbeat IPC | `ShutdownManager` supports a `:tcp` transport (localhost + port discovery file), used automatically on Windows; the Rust template implements the matching `#[cfg(windows)]` heartbeat |
| No graceful shutdown on Windows quit | Quitting clears `HEARTBEAT_ACTIVE`, stopping the heartbeat so the sidecar times out and exits gracefully (no SIGTERM needed) |
| CI/CD pipeline | `.github/workflows/ci.yml` runs unit/integration tests, E2E tests, and the full CLI flow on Linux |
| Duplicate command execution after LiveView reconnect | `TauriHook` removes the previous `handleEvent` callback before re-registering |
| Injection helpers corrupt UTF-8 files | `inject_js_hook`/`inject_layout_hook` now split on byte offsets (`binary_part`) matching regex `:index` returns |
| `cargo install` failures ignored | `install_tauri_cli` raises with an actionable message on non-zero exit |
| Cryptic `:enoent` when CLI missing | `run_tauri_cli` resolves the binary (including `.exe` on Windows) and points to `mix ex_tauri.install` |
| No Hex metadata or LICENSE | `mix.exs` has `description`/`package`/`docs`; MIT `LICENSE` file added |

---

## Remaining Work

### P0 — Critical for Production Use

| Feature | Details |
|---------|---------|
| Windows end-to-end validation | The Windows heartbeat path (TCP transport + port file) is implemented and unit-tested, but no Windows CI job builds and runs a real app yet. Add a `windows-latest` job. |

### P1 — Important for Adoption

| Feature | Details |
|---------|---------|
| Hex publication | Package metadata is now in mix.exs; remaining step is `mix hex.publish` (and a docs review on hexdocs). |
| System tray | Tauri V2 supports tray icons/menus. No integration exists. Important for long-running desktop apps. |
| Deep linking | `tauri-plugin-deep-link` for `myapp://` URL handling (OAuth, inter-app). |
| Global shortcuts | `tauri-plugin-global-shortcut` for app-wide keyboard shortcuts. |

### P2 — Nice to Have

| Feature | Details |
|---------|---------|
| Autostart | `tauri-plugin-autostart` for launch-at-login. |
| Runtime window management | Beyond initial config — minimize, maximize, set title, multi-window from LiveView. |
| Drag and drop | Tauri supports DnD events but no bridge to LiveView. |
| Compile-time config validation | Catch missing `:host`/`:port` at compile time, not runtime. |

### Architecture Considerations (Resolved)

1. ~~**Dev mode builds full Burrito release**~~ — Fixed. `mix ex_tauri.dev` now uses `run_dev/1` which builds a standard release and creates a shell wrapper script at the sidecar path. Burrito wrapping is only used by `mix ex_tauri.build` for production.

2. ~~**Single hook element bottleneck**~~ — Mitigated. `TauriHook` now implements `reconnected()` and `destroyed()` lifecycle callbacks. Commands in flight when the hook is destroyed are safely dropped. Reconnection re-attaches the event handler automatically.

3. ~~**OTP 27 hard constraint**~~ — Surfaced. `validate_config/0` and `preflight_check!/0` both check the OTP version and emit clear warnings/errors explaining the Burrito ERTS constraint and how to install OTP 27.
