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
| Fire-and-forget response handling | `use ExTauri.LiveView` routes responses to per-call callbacks; every API accepts a trailing `(result, socket) -> socket` fun. Manual `handle_event` clauses keep working |
| Dev mode was not hot reload | `mix ex_tauri.dev` now runs `mix phx.server` as the sidecar (code reloading + live reload in the native window); `--prod-sidecar` keeps the release path |
| Fixed port baked in at install | Rust picks an OS-assigned free port in production and passes `PORT`/`PHX_SERVER`/`PHX_HOST`/`SECRET_KEY_BASE` to the sidecar; window navigates to the real port. `EX_TAURI_PORT` pins it in dev |
| No sidecar→Tauri path without WebView | Heartbeat socket upgraded to a duplex NDJSON channel; `ExTauri.Desktop` sends notifications/tray commands from any process, native events delivered as messages |
| System tray | `ExTauri.Desktop.set_tray/1` builds/replaces the tray from Elixir; clicks arrive as `tray_menu_click` events |
| Multi-window | `ExTauri.Window.open/5` + `close/3` create and close labeled secondary windows |
| Deep linking | `mix ex_tauri.add deep-link` + `ExTauri.Event.subscribe(socket, "deep-link://new-url")` |
| No shipping guidance | `guides/releasing.md` (signing, notarization, updater manifests) + `guides/github-release-workflow.yml` CI matrix template |
| Example app predated the bridge | Example wired to the vendored hook, `withGlobalTauri`, and window/event capabilities |
| Linux-only CI | Added a macOS unit/integration test job |
| JS hook required npm packages | Bridge rewritten on the global Tauri API (`window.__TAURI__`, `withGlobalTauri: true` set by install) — a stock Phoenix esbuild setup bundles it with zero JS dependencies |
| Manual 3-file plugin setup | `mix ex_tauri.add <plugin>` patches Cargo.toml, main.rs, and capabilities idempotently for dialog, fs, clipboard, os, global-shortcut, autostart, process, updater |
| Runtime window management | `ExTauri.Window` — minimize/maximize/fullscreen/title/size/center/focus/hide/show/always-on-top/resizable/start-dragging/info |
| Drag and drop | `ExTauri.Event.subscribe(socket, "tauri://drag-drop")` forwards native events to `handle_event/3` as `"tauri_event"` |
| Global shortcuts | `ExTauri.GlobalShortcut` register/unregister/registered? with presses delivered as `"tauri_event"` |
| Autostart | `ExTauri.Autostart` enable/disable/status |
| App lifecycle | `ExTauri.App` info/exit/relaunch; `ExTauri.Updater.check/install` runtime API |

---

## Remaining Work

### P0 — Critical for Production Use

| Feature | Details |
|---------|---------|
| Hex publication | Package metadata is ready; remaining step is `mix hex.publish` (requires maintainer credentials). |

### P1 — Important for Adoption

| Feature | Details |
|---------|---------|
| Windows end-to-end validation | The Windows heartbeat/channel path (TCP transport + port file) is implemented and unit-tested, but no Windows CI job builds and runs a real app yet. |
| `mix ex_tauri.new` scaffold | One-command project creation (phx.new + install) — likely a separate archive package. |
| Richer desktop channel commands | The channel carries `notify` and `set_tray` today; native app menus defined from Elixir, dock badges, and window control without a LiveView are natural extensions. |

### P2 — Nice to Have

| Feature | Details |
|---------|---------|
| Targeting secondary windows | `ExTauri.Window` actions target the current window; addressing other labels (set title of the settings window from the main one) is not yet exposed. |
| Compile-time config validation | Catch missing `:host`/`:port` at compile time, not runtime. |

### Architecture Considerations (Resolved)

1. ~~**Dev mode builds full Burrito release**~~ — Fixed. `mix ex_tauri.dev` now uses `run_dev/1` which builds a standard release and creates a shell wrapper script at the sidecar path. Burrito wrapping is only used by `mix ex_tauri.build` for production.

2. ~~**Single hook element bottleneck**~~ — Mitigated. `TauriHook` now implements `reconnected()` and `destroyed()` lifecycle callbacks. Commands in flight when the hook is destroyed are safely dropped. Reconnection re-attaches the event handler automatically.

3. ~~**OTP 27 hard constraint**~~ — Surfaced. `validate_config/0` and `preflight_check!/0` both check the OTP version and emit clear warnings/errors explaining the Burrito ERTS constraint and how to install OTP 27.
