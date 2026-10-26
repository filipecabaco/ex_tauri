# CLAUDE.md — ex_tauri

`ex_tauri` is a **Hex library** that turns a Phoenix LiveView app into a native
desktop app (macOS/Windows/Linux) by wrapping [Tauri](https://tauri.app). This
file orients agents working **on the library**. For using it in an app, the
`.claude/skills/ex-tauri-*` skills below carry the detail.

## Skills (invoke before exploring)

| Task | Skill |
|------|-------|
| Call desktop APIs from LiveView (notifications, dialogs, clipboard, fs, window, events, shortcuts, updater) | `ex-tauri-apis` |
| Enable a Tauri plugin (`mix ex_tauri.add`) when an API no-ops | `ex-tauri-plugins` |
| Install/configure in an app, sidecar, non-Phoenix, DB/migrations | `ex-tauri-setup` |
| Build, sign, notarize, auto-update, CI | `ex-tauri-release` |
| **Change the library itself** (bridge, new API, Rust template, shutdown, version bump) | `ex-tauri-internals` |

`usage-rules.md` (repo root) is the condensed reference that ships with the Hex
package for consumers' agents — keep it in sync when the public API changes.

This is an Elixir project, so the `elixir:*` thinking skills (`elixir-thinking`,
`phoenix-thinking`, etc.) apply — invoke the relevant one before writing code.

## Hard rules

- **Never run `git commit`.** Stop and ask the user to commit.
- Use **`mise`** for version management, not asdf.
- **Tauri V2 only** in generated code; use semver **major ranges** (`"2"`,
  `--version ^2`), never pinned versions — pinning breaks consumers' builds.
- **OTP 27** only (Burrito precompiled ERTS); OTP 28 unsupported.
- `@version` in `mix.exs` is the single source of truth for the package version;
  a version bump must update the standalone projects or
  `test/version_consistency_test.exs` fails. `@latest_version` in
  `lib/ex_tauri.ex` is the default *Tauri* version — a different thing.
- Every user-facing change gets a `## [Unreleased]` entry in `CHANGELOG.md`.

## Layout

- `lib/ex_tauri/` — API modules + runtime (`hook`, `live_view`, `shutdown_manager`,
  `sidecar`, `plugins`, `paths`, `desktop`).
- `lib/mix/tasks/` — `install`, `dev`, `build`, `add`, `signer`, `icon`, `info`.
- `priv/templates/main.rs.eex`, `priv/static/ex_tauri.js` — generated Rust + JS bridge.
- `guides/releasing.md` — full release guide. `example/`, `demos/*`, `website/` — standalone apps.
- `test/` — unit + `--only integration` codegen contract + `e2e_*.sh` flows.

## Before pushing

```bash
MIX_ENV=test mix compile --warnings-as-errors
mix format
mix test
```
