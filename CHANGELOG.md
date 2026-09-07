# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/filipecabaco/ex_tauri/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.2.0
[0.1.0]: https://github.com/filipecabaco/ex_tauri/releases/tag/v0.1.0
