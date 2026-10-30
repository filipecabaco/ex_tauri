# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- iPhone and iPad: `mix ex_tauri.ios device` builds, signs, installs and
  launches the app on a real device. The backend runs inside the app, which is
  what iOS allows: `ampoule pack --target ios` (ampoule 0.1.9+) stages the
  release and `liberlang.xcframework`, the `build.rs` `init` now writes links
  ERTS in, and the shell boots the release with `erl_start` on a thread of its
  own. `mix ex_tauri.ios run` uses the same build in the simulator.
- Inside the iOS app, `ExTauri` loads `CAStore`'s bundle at boot, so
  `:public_key.cacerts_get/0`, and with it Req, Mint and `:ssl`, verify TLS on
  iOS, which lets no app read its trusted roots. `castore` is now a dependency.
- `ExTauri.ShutdownManager` has an `:in_process` transport, chosen with
  `EX_TAURI_IN_PROCESS=1`: for a BEAM running inside the app's own process, as on a
  real iPhone or iPad, which forbids starting the backend as a child process. It
  opens no listener and never stops on a missing heartbeat or an orphan check, since
  the VM ends exactly when the app does.

### Changed

- The iOS shell no longer starts the backend as a child process, packed by
  ampoule for the simulator, with a stdin heartbeat and restarts: it links ERTS
  in. A backend that halts ends the app. `mix ex_tauri.ios run` needs ampoule
  0.1.9+ with its iOS runtime; rerun `mix ex_tauri.ios init` to regenerate
  `lib.rs` and write `build.rs`.
- `init` keeps the signing team (`bundle.iOS.developmentTeam`) of an existing
  `tauri.ios.conf.json`, and every iOS build turns off the Xcode user script
  sandboxing that keeps Tauri's build phase from its options.

## [0.5.2] - 2026-10-27

### Fixed

- `igniter` and `burrito` are build-time dependencies (`runtime: false`), so they
  and everything they pull in (`rewrite`, `sourceror`, `owl`, ...) no longer ship
  inside every app's release. They are only ever used by the mix tasks and the
  Burrito release step, which still have them.

### Added

- `usage-rules.md` ships with the package: a condensed reference for agents
  working in an app that uses ex_tauri (setup, calling desktop APIs, plugins,
  packaging with Burrito or ampoule, and iPhone and iPad in the simulator).

## [0.5.1] - 2026-10-27

### Fixed

- `mix ex_tauri.ios init` pins the iOS minimum to 15.0 in `tauri.ios.conf.json`.
  Tauri CLIs before 2.12 default it to 14.0, which Xcode 27 refuses to build
  for, so `mix ex_tauri.ios run` failed for apps with an older CLI installed.
  An Xcode project already generated with 14.0 is raised in place on the next
  `init`, `build` or `run`; a higher minimum an app set itself is kept.

## [0.5.0] - 2026-10-27

### Added

- **iPhone and iPad, in the iOS simulator.** `mix ex_tauri.ios init` prepares
  `src-tauri` for iOS without touching the desktop build: an iOS shell in
  `src/lib.rs` (all `#[cfg(mobile)]`), a `[lib]` in `Cargo.toml` with
  `tauri-plugin-single-instance` moved to a desktop-only table, and a
  `tauri.ios.conf.json`. `mix ex_tauri.ios run` packs the release with ampoule
  for the Mac's architecture, bundles it into the app, and runs it there: the
  app starts it as a child process on loopback and points its window at it.
  `mix ex_tauri.ios dev` points the simulator at your dev server instead, live
  reload included. A device forbids starting a process and ampoule's
  executable memory, so this is simulator-only; see `guides/ios.md`.
  As on the desktop, a backend that dies under the open app is restarted on
  the same port (three times, with backoff) while the window says so; the app
  being suspended, locked or ended by iOS needs no help, since the backend's
  stdin, not a timer, decides when it stops.
- **The ampoule packager.** `config :ex_tauri, :packager, :ampoule` makes
  `mix ex_tauri.build` pack the release with
  [ampoule](https://github.com/filipecabaco/ampoule) instead of wrapping it with
  Burrito: one executable running the BEAM as WebAssembly on OTP 28, nothing to
  unpack on first launch. macOS and Linux. The release is built with
  `BURRITO_SKIP=true`; the generated shell recognises an ampoule sidecar by its
  trailer at launch, so `main.rs` and `tauri.conf.json` do not change.
- `ExTauri.Paths.documents_dir/0` — the user's documents folder; on iOS, the one
  the Files app shows for the app.
- `ExTauri.ShutdownManager` has a `:stdin` transport, chosen with
  `EX_TAURI_HEARTBEAT_STDIN=1`: no listener, and the backend stops when stdin
  closes. The iOS shell uses it, since a Unix socket path inside a simulator's
  app container is longer than macOS allows.

### Changed

- `ExTauri.Paths` honours `EX_TAURI_HOME` and `EX_TAURI_HOST_OS` (`macos`, `ios`,
  `linux`), which the generated shells set for an ampoule sidecar: its own home
  is a private `/tmp` deleted on exit, and it reports Linux on every host — so
  without them its data would vanish, or land in `~/.local/share` on a Mac.
- The OTP version check follows the packager: OTP 27 for Burrito, OTP 28 for
  ampoule. A backend an iOS or ampoule shell started (`EX_TAURI_HOST_OS` set) is
  held to OTP 28 whatever `:packager` says for the desktop build.
- `mix ex_tauri.build --target <triple>` now packages the sidecar for that
  triple rather than the host's.

## [0.4.2] - 2026-10-20

### Fixed

- **A restarted backend could leave App Nap disabled for good.** The shell held
  the `keep_awake` activity across a backend restart, while the new backend
  started out believing nothing was held — so with no work in progress it never
  sent `keep_awake(false)`. The shell now releases the activity whenever the
  sidecar exits. Found by killing the BEAM under a real build.

## [0.4.1] - 2026-10-20

### Fixed

- **Quitting from the Dock, an AppleScript `quit` or logging out skipped the
  shell's shutdown.** macOS terminates the app itself there and Tauri reports
  only `RunEvent::Exit`, never the `ExitRequested` the shell handled, so the
  backend got no SIGTERM and was left to notice the heartbeat socket closing
  (about three seconds later, and not through its own shutdown). The shell now
  stops the sidecar on `Exit` too. Found by quitting a real build and reading
  its log: no "stopping" line, no exit line.

## [0.4.0] - 2026-10-20

The generated Rust shell (`priv/templates/main.rs.eex`) is rewritten around
what a desktop backend actually does in the field: start slowly, die, get
throttled, and leave nothing behind to say why. Regenerate `src-tauri/src/main.rs`,
`Cargo.toml`, `tauri.conf.json`'s window and `capabilities/default.json` with
`mix ex_tauri.install` to pick it up.

### Added

- **The backend is restarted when it dies under an open window**, on the same
  port, up to three times with backoff (a backend that stayed up a minute gets
  a fresh three). Until then, and if it gives up, the window shows a page saying
  what happened, the exit code or signal, and where the log is — instead of
  polling a dead port for as long as it stays open.
- **A loading page and a startup error page.** The window opens on a `data:`
  "Starting…" page rather than `frontendDist` (whatever was listening on the
  configured port of the user's machine, with the app's capabilities), and a
  backend that never comes up gets a page naming the reason.
- `ExTauri.Desktop.keep_awake/1` holds off macOS App Nap (an `NSProcessInfo`
  activity) while your app is doing work someone is waiting on. App Nap
  throttles a hidden window's timers, the heartbeat thread's included.
- `ExTauri.Desktop.quit/0` quits the app the way its Quit menu item does.
- A `"heartbeat_late"` desktop event, sent once when the shell's heartbeat
  starts running late (`%{"late_ms" => n}`), and logged by the shell.
- `ExTauri.Sidecar.Orphan.shell_pid/0`: the shell now passes its own pid as
  `EX_TAURI_SHELL_PID`, and the orphan and live-shell checks ask about it.

### Fixed

- **Burrito 1.6 broke shutdown and orphan detection.** Up to 1.5 the launcher
  `execve`d the BEAM; from 1.6 it spawns the BEAM as its child. The shell's
  SIGTERM killed the launcher, logged "shut down gracefully", and left the BEAM
  running; `orphan?/0` and `shell_alive?/0` were asking about the launcher; and
  the window's `--no-halt` made every sidecar look like a CLI invocation, so
  none was ever reaped. The shell now signals the BEAM itself and spawns the
  sidecar in its own process group (the final kill takes the launcher and any
  port programs with it), the Elixir checks use `EX_TAURI_SHELL_PID` or look
  past a launcher to the shell, and `--no-halt` alone is not a command.
- **The generated shell never passed `--no-halt`**, which Burrito 1.6 needs or
  it halts the VM right after boot.
- **The generated shell waited for the backend on the main thread, forever**:
  a spinning cursor and a window that could not be quit when it never came up.
  The wait is on a worker thread with a two-minute deadline, and stops the
  moment the sidecar exits.
- **The sidecar's output and exit were lost.** Stdout was `println!`ed (nowhere,
  for an app launched from Finder) and stderr and the exit dropped. They go to
  the app's log, with Elixir's `[error]`/`[warning]` carried over as log levels
  and colour codes stripped. `ERL_CRASH_DUMP` points next to the log: the BEAM
  wrote dumps to its working directory, `/` for an app launched from Finder.
- **The app's log deleted itself.** The log plugin's defaults keep one 40 KB
  file at TRACE level and delete it when it fills; it is now INFO, 5 MB, five
  files kept, local timestamps.
- **The generated capabilities did not apply to the app's real page.** Tauri
  counts a page as local only under `frontendDist`, and the shell navigates to
  an ephemeral port, so every invoke from the page was denied in production
  while working in dev. They now carry `remote: <scheme>://<host>:*`.
- **A new window could attach to an abandoned backend.** The heartbeat socket
  was named for the app only; it is now per launch and passed to the sidecar as
  `EX_TAURI_HEARTBEAT_SOCKET` (`EX_TAURI_HEARTBEAT_PORT_FILE` on Windows).
  `ExTauri.ShutdownManager` listens there when set.
- **`set_tray` added a new icon every call** and multiplied every click (a
  listener per call, never removed), and **any menu or tray id containing
  "quit" quit the app**. The old icon is removed first, tray clicks are routed
  once, the Quit item's id is namespaced, and tray clicks are no longer also
  reported as `menu_click`.
- **Quitting blocked the UI thread** (two seconds on every Windows quit) and
  ended with `process::exit`, skipping plugin cleanup. It runs on a worker
  thread and ends with `AppHandle::exit`.
- `expect` on a missing or unstartable sidecar panicked with no trace; it now
  shows the startup error page, and a panic hook logs any panic.
- The channel could hang forever writing to a backend that stopped reading, and
  its reader could die silently on a bad line, after which every command was
  dropped. Writes time out and both sides reconnect together.
- Opening the app again, or clicking its Dock icon, brings the window back.

### Changed

- The generated capability no longer grants `shell:allow-execute` for the
  sidecar. The Rust shell spawns it, capabilities do not restrict Rust, and
  with `remote` set it would let any page on the host start another copy of the
  backend. Add it back to `capabilities/default.json` only if your page really
  starts the sidecar itself.
- The generated `Cargo.toml` needs `tauri-plugin-shell` 2.5 (`set_process_group`),
  the `webview-data-url` feature, and `objc2`/`objc2-foundation` on macOS.
- **Requires Burrito `~> 1.6`, and with it Elixir `~> 1.17` and Zig 0.16.0**
  for `mix ex_tauri.build`. `~> 1.5` already resolved to 1.6.0 for every new
  app; the generated shell and the orphan checks are now built around its
  launcher (which spawns the BEAM as a child), so the requirement says so.

## [0.3.0] - 2026-10-20

### Added

- `ExTauri.Sidecar.Orphan` — finds and stops packaged sidecars whose window is
  gone. Call `ensure_port_available/2` from `Application.start/2` before your
  endpoint's child spec: it evicts an abandoned sidecar squatting the port, then
  sweeps the orphans that hold no port but keep running timers, pollers and
  child processes with nothing to show them in. Two apps on one machine had
  accumulated seven and four of these respectively, the oldest holding its port
  for three and a half days so that every later launch died on `:eaddrinuse`
  with a hand-typed `pkill` as the only remedy.

  Eviction is scoped to *your* release. Burrito names its unpack directory after
  the release, `mix ex_tauri.install` scaffolds that release as `:desktop` for
  everyone, and so two ex_tauri apps share `.burrito/desktop_erts-*`: a sweep
  that matched on the path alone would SIGTERM the other app's running sidecar.
  `identify/2` reads the payload instead (`lib/<otp_app>-<vsn>`), and answers
  `:unknown` — never `:foreign` — for an unpack directory that has been deleted
  out from under a live process, which is what an upgrade leaves behind.

### Changed

- **`mix ex_tauri.install` now names the release after your application**
  (`:my_app_desktop`) rather than `:desktop`, and records it as `config
  :ex_tauri, :release_name`. Burrito names its unpack directory after the
  release and nothing else, so scaffolding `:desktop` for everyone put every
  ex_tauri app on a machine into one shared `.burrito/desktop_erts-*` — which is
  what made a sidecar's owner unknowable from its path, and what let a sweep for
  abandoned ones reach another vendor's running app. An app-derived name makes
  that collision impossible rather than merely detectable.

  Nothing changes for an existing app. `:release_name` defaults to `"desktop"`,
  and the installer keeps a `:desktop` release that is already in `mix.exs`
  rather than renaming it — renaming would orphan the sidecar binary it has
  already built and the `tauri.conf.json` entry pointing at it. Existing apps
  can migrate by renaming the release, setting `:release_name` to match, and
  rebuilding; `ExTauri.Sidecar.Orphan`'s payload check protects them either way.

  The name is now threaded through everything that has to agree on it: the
  release Mix builds, `_build/prod/rel/<name>/bin/<name>`,
  `burrito_out/<name>-<triple>`, `externalBin` and the `shell:allow-execute`
  capability in the generated Tauri config, and the `sidecar("<name>")` call in
  `main.rs`.

### Fixed

- `ExTauri.ShutdownManager` gained three stop signals and lost a crash, all from
  sidecars found outliving their windows in the field:

  - **The connection closing** now ends the backend once
    `:heartbeat_reconnect_grace` (3s) passes with nothing reconnecting. The
    kernel closes a dead process's sockets, so this is the signal a crash or a
    force-quit actually trips, and it no longer waits on bytes to stop.
  - **A check that runs late rebaselines** instead of shutting down. Both sides
    freeze when the machine sleeps, they do not resume together, and the
    monotonic clock keeps running across the sleep — an ordinary lid-close read
    as `heartbeat timeout (1610ms)` and killed the backend with the window still
    on screen. A check more than `:heartbeat_stall_grace` (1s) later than it was
    scheduled proves this process was not running either.
  - **A heartbeat that never arrived** is no longer immortal. The startup grace
    makes that state deliberately unkillable so a slow boot cannot kill itself,
    which left a sidecar whose shell died before it could connect running until
    the machine rebooted. After `:heartbeat_orphan_grace` (60s) with nothing
    heard, a packaged sidecar that has been reparented to init stops itself.
  - **A socket path another instance owns no longer crashes the tree.** The
    unmatched `{:ok, socket} = :gen_tcp.listen(...)` turned that into a crash
    loop that took the whole supervision tree with it; it now degrades to a
    manager with no listener, keeping the orphan check — the one signal that
    does not need the socket — alive to stop the process properly.

- `ExTauri.ShutdownManager` no longer unlinks a heartbeat socket another
  instance is listening on. The unconditional `File.rm/1` on startup meant a
  second sidecar booting, or dying seconds later and running `terminate/2`,
  deleted the live instance's socket file: that listener survived but became
  unreachable, its window could never reconnect, and — the heartbeat having
  never arrived — it then ran forever holding its port. A stale path with
  nothing listening is still removed, which is the case that check was for.

- `ExTauri.ShutdownManager` no longer stops the backend when a heartbeat goes
  quiet under a shell that is still running. macOS App Nap throttles the timers
  of an app whose window has been hidden for a while, heartbeat thread included,
  so the bytes arrive late while the socket stays open and the window is fine.
  One such gap stopped a backend that six agents were driving, after its window
  had been in the background for fifteen minutes. On Unix, in a packaged build, a
  timeout with the connection still open now asks the new
  `ExTauri.Sidecar.Orphan.shell_alive?/0` first. A shell that is still the
  sidecar's parent keeps the backend up, and the stall is logged when it starts
  and when it ends. A quit (SIGTERM), a closed socket and a shell that died
  (reparented to init) all still stop it. Windows, whose frontend quits by
  letting the heartbeat time out, keeps the plain timeout, and so does
  `mix ex_tauri.dev`. The check can be replaced with `:shell_alive_check`.

## [0.2.0] - 2026-07-12

### Added

- Configurable sidecar shims via the `ExTauri.Sidecar` behaviour and a
  `:sidecars` registry, so any launcher can replace the built-in ones.
- `:dev_command` config to choose the command the dev sidecar runs
  (e.g. `~w(mix francis.server)`), defaulting to `mix phx.server`.
- `:sidecar_env` config to inject extra environment variables into the
  production sidecar, defaulting to Phoenix's `PHX_SERVER`/`PHX_HOST`.
  `PORT` and `SECRET_KEY_BASE` are always injected.
- `--sidecar <name>` option for `mix ex_tauri.dev` to select a sidecar.
- Francis end-to-end flow test and a `francis-flow-test` CI job, exercising
  the framework-agnostic path.
- `ExTauri.version/0` as the single source of truth for the package version.
  Runtime-reachable version strings (the generated `Cargo.toml`, test
  fixtures) now derive from it, and `version_consistency_test` fails the
  build if a standalone project (`example/`, `website/`, `demos/*`) drifts
  from the package version after a bump.

### Changed

- ex_tauri is no longer coupled to Phoenix: the dev command and production
  sidecar environment are configurable, allowing frameworks such as Francis.

### Deprecated

- `mix ex_tauri.dev --prod-sidecar` in favor of `--sidecar release`.

## [0.1.0]

Initial release.

[Unreleased]: https://github.com/filipecabaco/ex_tauri/compare/v0.5.2...HEAD
[0.5.2]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.5.2
[0.5.1]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.5.1
[0.5.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.5.0
[0.4.2]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.4.2
[0.4.1]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.4.1
[0.4.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.4.0
[0.3.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.3.0
[0.2.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.2.0
[0.1.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.1.0
