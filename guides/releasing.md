# Releasing Your Desktop App

This guide covers the path from a working `mix ex_tauri.dev` app to signed,
distributable artifacts with auto-updates.

## 1. Production build

```bash
mix ex_tauri.build
```

This builds your Elixir release, wraps it with Burrito into a single binary
sidecar, and bundles platform packages into `src-tauri/target/release/bundle/`:

| Platform | Artifacts |
|----------|-----------|
| macOS    | `.app`, `.dmg` |
| Linux    | `.deb`, `.appimage` |
| Windows  | `.msi`, `.exe` (NSIS) |

At runtime the app picks a **free ephemeral port** for Phoenix (no collisions
with other software) and passes `PORT`, `PHX_SERVER=true`, `PHX_HOST`, and a
generated `SECRET_KEY_BASE` to the sidecar — the standard Phoenix
`config/runtime.exs` picks these up without modification.

## 2. Code signing

Unsigned apps trigger OS warnings (macOS Gatekeeper blocks them outright for
downloaded apps). Tauri signs during `mix ex_tauri.build` when these
environment variables are set:

### macOS (signing + notarization)

```bash
export APPLE_CERTIFICATE="base64 encoded .p12"
export APPLE_CERTIFICATE_PASSWORD="p12 password"
export APPLE_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Notarization (required for distribution outside the App Store):
export APPLE_ID="you@example.com"
export APPLE_PASSWORD="app-specific password"
export APPLE_TEAM_ID="TEAMID"
```

### Windows

Set `certificateThumbprint`, `digestAlgorithm`, and `timestampUrl` under
`bundle > windows` in `src-tauri/tauri.conf.json`, or use an EV certificate
provider's signing tool in CI. See the
[Tauri distribution docs](https://v2.tauri.app/distribute/) for details.

## 3. Auto-updates

1. Generate a signing keypair (once, keep the private key secret):

   ```bash
   mix ex_tauri.signer generate
   ```

2. Configure the updater and rerun `mix ex_tauri.install`'s config step or edit
   `config/config.exs`:

   ```elixir
   config :ex_tauri,
     updater: [
       enabled: true,
       endpoints: ["https://github.com/you/yourapp/releases/latest/download/latest.json"],
       pubkey: "PUBLIC_KEY_FROM_STEP_1"
     ]
   ```

3. Install the updater plugin: `mix ex_tauri.add updater process`

4. Build with the private key in the environment — Tauri then emits
   `.sig` files next to each bundle:

   ```bash
   export TAURI_SIGNING_PRIVATE_KEY="content of the private key"
   export TAURI_SIGNING_PRIVATE_KEY_PASSWORD="password"
   mix ex_tauri.build
   ```

5. Publish the bundles plus a `latest.json` manifest at your endpoint:

   ```json
   {
     "version": "1.2.0",
     "notes": "Bug fixes",
     "pub_date": "2026-07-08T00:00:00Z",
     "platforms": {
       "darwin-aarch64": {
         "signature": "content of the .app.tar.gz.sig file",
         "url": "https://github.com/you/yourapp/releases/download/v1.2.0/YourApp_aarch64.app.tar.gz"
       },
       "linux-x86_64": {
         "signature": "content of the .AppImage.sig file",
         "url": "https://github.com/you/yourapp/releases/download/v1.2.0/your-app_1.2.0_amd64.AppImage"
       }
     }
   }
   ```

6. In the app, check and apply updates from LiveView:

   ```elixir
   socket =
     ExTauri.Updater.check(socket, fn
       {:ok, %{"available" => true, "version" => version}}, socket ->
         assign(socket, update_available: version)

       _result, socket ->
         socket
     end)

   # Later, on user confirmation:
   socket = ExTauri.Updater.install(socket, fn {:ok, _}, socket ->
     ExTauri.App.relaunch(socket)
   end)
   ```

## 4. CI release workflow

A ready-to-adapt GitHub Actions workflow lives at
[`guides/github-release-workflow.yml`](github-release-workflow.yml). It builds
on a macOS/Linux/Windows matrix, signs when secrets are configured, and
uploads the bundles to a GitHub release. Copy it to
`.github/workflows/release.yml` in your app and adjust the app name.

## Notes and constraints

- **Cross-compilation** is limited: build each platform's artifacts on that
  platform (the CI matrix handles this). Burrito can cross-wrap the BEAM, but
  Tauri's bundler and signing are per-OS.
- **OTP 27** is required for Burrito's precompiled ERTS (see README).
- Sessions are signed with a per-launch `SECRET_KEY_BASE` by default; set the
  env var yourself (e.g. store one in the app's data dir) if you need sessions
  to survive restarts.
