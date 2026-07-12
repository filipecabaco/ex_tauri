# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
