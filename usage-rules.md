# ExTauri usage rules

ExTauri turns a Phoenix LiveView app into a native desktop app (macOS/Windows/Linux)
by wrapping [Tauri](https://tauri.app). Tauri launches your app as a **sidecar
process**; the WebView renders your LiveView over HTTP; a local socket carries a
heartbeat + a duplex desktop channel.

<!-- usage-rules-start -->

## Setup

- Requires **Elixir ≥ 1.17** and **Rust** (rustup), on **OTP 27** for Burrito
  builds (its precompiled ERTS stops at 27) or **OTP 28** for the ampoule
  packager and iOS. Add `{:ex_tauri, "~> 0.6"}`, then `mix deps.get` and
  `mix ex_tauri.install`.
- `mix ex_tauri.install` is Igniter-driven and idempotent: it sets
  `app_name`/`host`/`port`/`version` config, scaffolds `src-tauri/`, adds
  `ExTauri.ShutdownManager` to the supervision tree, adds a release named
  `<otp_app>_desktop` (an app that already has a `:desktop` release keeps it;
  `config :ex_tauri, release_name:` wins over both), and injects the JS hook +
  `<div id="tauri-bridge">`.
- Run in a native window with hot reload: `mix ex_tauri.dev`. Build for prod:
  `mix ex_tauri.build`.
- Config lives under `config :ex_tauri` — `app_name`, `host`, `port` are
  required; `app_name` also keys the heartbeat socket and all `ExTauri.Paths` dirs.

## Calling desktop APIs from LiveView

- Add `use ExTauri.LiveView` to any LiveView that calls ExTauri APIs. It routes
  bridge responses to the **callback you pass as the last argument** — do not
  hand-write `handle_event("tauri_response", ...)` unless you deliberately skip
  the callback style.
- Reply callbacks are `fn {:ok, payload} | {:error, reason}, socket -> socket end`
  (one-shot). Event handlers (`Event.subscribe/3`, `GlobalShortcut.register/3`)
  are `fn payload, socket -> socket end` (persistent). **Both must return the socket.**
- Payload maps use **string keys** (they come from JS): `%{"path" => path}`,
  `%{"text" => text}`, etc.
- Subscribe to events in `mount/3` guarded by `connected?/1` — subscriptions are
  torn down on navigation and must be re-established.

```elixir
def handle_event("pick_file", _p, socket) do
  socket = ExTauri.Dialog.open(socket, [title: "Pick a file"], fn
    {:ok, %{"path" => path}}, socket -> assign(socket, :file, path)
    {:error, _}, socket -> put_flash(socket, :error, "cancelled")
  end)
  {:noreply, socket}
end
```

## Plugins: an API doing nothing usually means a missing plugin

- Out of the box: `ExTauri.Notification`, `ExTauri.Shell`, `ExTauri.Window`,
  `ExTauri.Event` (core), `ExTauri.App.info`.
- Need `mix ex_tauri.add <plugin>`: `dialog` → `Dialog`, `fs` → `Filesystem`,
  `clipboard` → `Clipboard`, `os` → `OS`, `global-shortcut` → `GlobalShortcut`,
  `autostart` → `Autostart`, `process` → `App.exit`/`relaunch`, `updater` →
  `Updater`, `deep-link` → deep links via `Event`.
- `mix ex_tauri.add` is idempotent; rebuild with `mix ex_tauri.dev` after adding.
  `deep-link` also needs its scheme declared in `src-tauri/tauri.conf.json`.

## Server-side (no LiveView)

- `ExTauri.Desktop.notify/2` and `ExTauri.Desktop.set_tray/1` work from any
  process (GenServer, Oban, PubSub) over the internal channel. Subscribe with
  `ExTauri.Desktop.subscribe/0`; tray clicks arrive as
  `{:ex_tauri_event, "tray_menu_click", %{"id" => id}}`.
- Use `ExTauri.Paths.{data_dir,config_dir,cache_dir,log_dir}/0` for any
  filesystem path (DB, logs, config). **Never hardcode `/tmp` or `~/`.**

## Sidecars that outlive their window

- Call `ExTauri.Sidecar.Orphan.ensure_port_available(port)` at the very top of
  `Application.start/2`, before the endpoint's child spec. A sidecar whose shell
  died is reparented to init and keeps running — holding your port, so the next
  launch dies on `:eaddrinuse`, and running timers and pollers with no window.
  This evicts the one squatting the port and sweeps the rest.
- It only ever signals **your** release. Burrito names its unpack directory
  after the release, and installs before 0.4 all scaffolded `:desktop`, so two
  such apps share `.burrito/desktop_erts-*`; the payload (`lib/<otp_app>-<vsn>`)
  is what tells them apart. Pass `:otp_app` if your OTP app is not the
  sanitised `:app_name`, and `:release_name` if your release is not the one in
  `config :ex_tauri, :release_name` (default `"desktop"`).
- `ExTauri.ShutdownManager` handles the rest by itself once it is in your tree:
  it stops on a closed connection, on a heartbeat that stops, and — in a
  packaged build only — on a sidecar that never got a heartbeat and has lost its
  parent. Tune with `:heartbeat_reconnect_grace`, `:heartbeat_stall_grace` and
  `:heartbeat_orphan_grace` if the defaults (3s / 1s / 60s) do not fit.

## Desktop specifics (Ecto)

- Put the SQLite DB under `ExTauri.Paths.data_dir()` in `config/runtime.exs`.
- Releases don't run `mix ecto.migrate`; call a `Release.migrate/0` at the top
  of `Application.start/2` before the Repo's children serve traffic.

## Production

- The release `mix ex_tauri.install` added needs `steps: [:assemble,
  &Burrito.wrap/1]` and a `burrito: [targets: [...]]`. Build each OS's bundles
  on that OS.
- Or pack it with [ampoule](https://github.com/filipecabaco/ampoule) instead:
  `config :ex_tauri, :packager, :ampoule` makes `mix ex_tauri.build` produce
  one executable running the BEAM as WebAssembly on OTP 28, with nothing to
  unpack (macOS and Linux; no Windows). `ampoule` must be on PATH, or set
  `config :ex_tauri, :ampoule_path`. `main.rs` tells the two apart at launch.
- Signing runs during `mix ex_tauri.build` when the platform env vars are set
  (`APPLE_*` on macOS; thumbprint/timestamp on Windows). Auto-updates need
  `mix ex_tauri.signer generate`, the `updater` config block, the `updater`
  plugin, and `TAURI_SIGNING_PRIVATE_KEY` at build time.

## Not tied to Phoenix

- The dev command is `config :ex_tauri, :dev_command` (default `mix phx.server`)
  and prod env injection is `:sidecar_env`. `PORT` and `SECRET_KEY_BASE` are
  always injected — your app must bind the injected `PORT`. The native API
  bridge is Phoenix LiveView-only today; other frameworks get window + lifecycle.
- In production `PORT` is an **OS-assigned ephemeral port**, not your configured
  `:port` — binding a hardcoded port gives a blank window with no error. Phoenix
  reads `PORT` on its own; Francis needs one line in `config/runtime.exs`:

  ```elixir
  if port = System.get_env("PORT") do
    config :francis, bandit_opts: [ip: {127, 0, 0, 1}, port: String.to_integer(port)]
  end
  ```

- **That recipe requires francis >= 0.3.4.** On 0.3.3 and earlier, Francis reads
  `:bandit_opts` from the `use Francis` macro options only and silently discards
  the application config, binding Bandit's default 4000. On older Francis put the
  port in the macro options instead — they are spliced into the generated
  `start/2`, so `System.get_env("PORT")` is still read at boot.

## iPhone and iPad

- `mix ex_tauri.ios init` once, then `mix ex_tauri.ios run` (the simulator, as
  it ships), `mix ex_tauri.ios device` (an iPhone or iPad) or
  `mix ex_tauri.ios dev` (the simulator on your dev server, live reload). Needs
  Xcode, and for `run`/`device` ampoule 0.1.9+ with its iOS runtime, on OTP 28.
- The BEAM runs inside the app (iOS starts no other process): `init` writes the
  iOS shell to `src-tauri/src/lib.rs` (all `#[cfg(mobile)]`, the desktop build is
  untouched), a `build.rs` that links ERTS in, a `[lib]` in `Cargo.toml`,
  `tauri.ios.conf.json`, and a loading page in `src-tauri/mobile/index.html`
  that is yours to restyle. It refuses a `lib.rs` or `build.rs` with code of its
  own unless `--force`.
- `device` needs a signing team: an Apple ID in Xcode, and its team ID in
  `tauri.ios.conf.json` (`bundle.iOS.developmentTeam`), kept across `init`.
- No `System.cmd`/ports to programs, and no NIFs beyond OTP's (crypto, asn1).
  TLS verifies against the bundled CA store ExTauri loads at boot
  (`:public_key.cacerts_get/0` returns it); DNS uses Erlang's resolver.
- Keep files under `ExTauri.Paths` — on iOS they resolve inside the app's
  container; `ExTauri.Paths.documents_dir/0` is the folder the Files app shows.
- The app reloads its page when iOS reclaims it, and a new BEAM starts when the
  app is opened again. Browser storage does not survive a launch (the origin's
  port changes), so keep state that must survive (open document, unsaved edits)
  with the backend, under `ExTauri.Paths.config_dir/0`.
- Lay out for the phone and the tablet with CSS media queries and
  `env(safe-area-inset-*)`, with `viewport-fit=cover` in the viewport meta.
  `"__TAURI__" in window && navigator.maxTouchPoints > 0` is the shell on
  iPhone or iPad; on the Mac `maxTouchPoints` is 0.
- `ExTauri.Desktop` (tray, server-side notifications) answers
  `{:error, :not_connected}` on iOS.

<!-- usage-rules-end -->
