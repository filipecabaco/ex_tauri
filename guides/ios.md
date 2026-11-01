# iPhone and iPad

`mix ex_tauri.ios` runs your app on iPhone and iPad, in the simulator and on a
real device, with the same Elixir backend and the same UI as the desktop build.

```bash
mix ex_tauri.ios init      # once: prepare src-tauri for iOS
mix ex_tauri.ios dev       # the simulator on your dev server, live reload
mix ex_tauri.ios run       # the simulator, as it would ship
mix ex_tauri.ios device    # an iPhone or iPad, as it would ship
```

iOS lets an app start no other process, and a device maps no executable
memory, so the backend runs **inside the app**. ERTS, the Erlang runtime, is
linked in as ordinary signed code (`liberlang.xcframework`, from
[ampoule](https://github.com/filipecabaco/ampoule)), and the app boots your
release on a thread of its own. The simulator and a device run the same build.

## Requirements

- Xcode with an iOS simulator runtime (`xcrun simctl list runtimes`)
- The Rust iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
- For `run` and `device`: [ampoule](https://github.com/filipecabaco/ampoule/releases)
  **0.1.9 or later** on `PATH` (or `config :ex_tauri, :ampoule_path, "..."`),
  with its iOS runtime (the `ios/` directory its macOS release carries, or
  `AMPOULE_IOS_RUNTIME`), and **OTP 28**, the OTP of that runtime. `dev` needs
  neither.
- For `device`, a signed app:
  - an Apple ID in Xcode (Settings > Accounts). A free Personal Team works, but
    its installs stop opening after 7 days; a paid account's last a year;
  - its team ID in `src-tauri/tauri.ios.conf.json`
    (`"bundle": {"iOS": {"developmentTeam": "ABCDE12345"}}`) or
    `APPLE_DEVELOPMENT_TEAM`. Rerunning `init` keeps it;
  - the iPhone or iPad paired (connect it once by cable, unlock it, tap
    **Trust**) with **Developer Mode** on (Settings > Privacy & Security).

## Preparing the project

`mix ex_tauri.ios init` touches five files and leaves the desktop build alone:

| File | What changes |
|------|--------------|
| `src-tauri/src/lib.rs` | The iOS shell. Replaces the stub `cargo tauri init` leaves there; refuses a `lib.rs` with code of its own unless `--force`. Everything in it is `#[cfg(mobile)]`, so the desktop crate compiles past it. |
| `src-tauri/build.rs` | Links ERTS into iOS builds from the staged runtime, and turns on the code that starts it. Desktop builds are unchanged. Replaces Tauri's own `build.rs`; refuses one with code of its own unless `--force`. |
| `src-tauri/Cargo.toml` | A `[lib]` the iOS build links, and `tauri-plugin-single-instance` moved to a desktop-only table (only `main.rs` uses it, and it does not build for iOS). |
| `src-tauri/tauri.ios.conf.json` | Merged over `tauri.conf.json` for iOS: the staged release as a resource instead of a sidecar, a bundled loading page, an identifier iOS accepts. The signing team is kept. |
| `src-tauri/mobile/index.html` | The loading page. Written only when missing: restyle it in the app's own look, and rerunning `init` keeps it. |

It then runs `cargo tauri ios init` to generate the Xcode project in
`src-tauri/gen/apple`. Rerunning `init` is safe; it regenerates only what it
wrote. To change the app's `identifier` later, delete `src-tauri/gen/apple`
and rerun `init`: the generated project keeps the identifier it was made with.

## Running it

### `mix ex_tauri.ios dev` — while you build the UI

Builds the shell without a backend and launches it pointed at
`http://<:host>:<:port>`, and runs your `:dev_command` in the foreground. The
simulator shares the Mac's network, so the window loads your dev server and
**live reload works** — edit CSS, see the iPhone update.

### `mix ex_tauri.ios run` — the simulator, as it would ship

Builds the release (with `BURRITO_SKIP=true`), stages it with
`ampoule pack --target ios` in `_build/ex_tauri_ios/` (the release the bundle
carries and `liberlang.xcframework`), builds the app, installs it in the
simulator and launches it. Nothing else is involved: no dev server, no network.

### `mix ex_tauri.ios device` — an iPhone or iPad

The same staging, built for the device and signed with your team, then
installed and launched with `xcrun devicectl`. The device must be unlocked to
install and launch; the first time, trust your developer profile in Settings >
General > VPN & Device Management.

### Options

- `--device NAME|UDID` — which simulator (`run`, `dev`) or device (`device`).
  A simulator defaults to one already booted, else the first iPad; a device to
  the first one connected. Try `--device "iPhone 17 Pro"` for the phone layout.
- `--console` — stay attached and print the app's output.
- `--allow-older-runtime` — see [Troubleshooting](#troubleshooting).

The simulator window is **Simulator.app**, or on Xcode 27 **DeviceHub**
(`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`); the task opens
whichever is installed.

## How the backend runs

```
iOS app (Tauri shell, src-tauri/src/lib.rs + build.rs)
  │  links liberlang.xcframework: ERTS, OTP's crypto/asn1 NIFs, OpenSSL
  │  calls erl_start(argc, argv) on a thread of its own
  ▼
your release, from the bundle  ── serves your UI on 127.0.0.1:<free port>
  ▼
WKWebView  ── loads it, LiveView socket included
```

The shell does what a release's start script would: it copies `sys.config` to
a writable place for your `runtime.exs`, sets the `RELEASE_*` variables, and
boots the release's own boot script. It also passes:

| Variable | Read by | Why |
|----------|---------|-----|
| `EX_TAURI_HOME` | `ExTauri.Paths` | the app's sandbox container |
| `EX_TAURI_HOST_OS=ios` | `ExTauri.Paths` | iOS paths, not macOS's |
| `EX_TAURI_IN_PROCESS=1` | `ExTauri.ShutdownManager`, `ExTauri` | the `:in_process` transport; and the bundled CA store, loaded at boot |
| `ERL_INETRC` | `:inet` | name lookups through Erlang's own DNS client |
| `PORT`, `SECRET_KEY_BASE`, `:sidecar_env` | your app | as on the desktop |

### Where to keep files

Use `ExTauri.Paths`, which resolves inside the app's container on iOS:

- `ExTauri.Paths.data_dir/0`, `config_dir/0`, `cache_dir/0` — app state
- `ExTauri.Paths.documents_dir/0` — files the user owns; on iOS this is the
  folder the Files app shows for your app

Code that reads `System.user_home!/0` or `XDG_*` directly gets the container
too (`HOME` is set to it), but not the platform's conventions. For an app with
its own setting, pick the root in `config/runtime.exs`:

```elixir
if System.get_env("EX_TAURI_HOST_OS") == "ios" do
  config :my_app, root: ExTauri.Paths.documents_dir()
end
```

### What behaves differently

- **No other processes.** `System.cmd/3`, ports to programs, and anything that
  shells out fail: iOS starts none.
- **No native code beyond OTP's.** OTP's crypto and asn1 NIFs are linked in;
  `ampoule pack --target ios` refuses a release with other NIFs (exqlite,
  Rustler crates) unless `--allow-native`, which leaves them out.
- **TLS verifies against a bundled CA store.** iOS lets no app list its trusted
  roots, so `ExTauri` loads `CAStore`'s bundle at boot and
  `:public_key.cacerts_get/0` returns it: Req, Mint, `:httpc` and `:ssl` with
  `cacerts: :public_key.cacerts_get()` work unchanged.
- **DNS goes through Erlang's resolver**, not the system's: the shell writes an
  `inetrc` with public resolvers as fallback (`8.8.8.8`, `1.1.1.1`).
- **No desktop channel.** `ExTauri.Desktop` (tray, server-side notifications)
  answers `{:error, :not_connected}`.

### Sleep, suspension, and crashes

| What happens | What the app does |
|--------------|-------------------|
| The app goes to the background, or the device locks | iOS suspends the whole app, BEAM included; it carries on when the app comes back. Connections may have dropped meanwhile: reconnect on failure. iOS may also have reclaimed listening sockets, the app's own HTTP endpoint included: `ExTauri.Resume` (below) listens again |
| iOS reclaims the suspended app's web content | WebKit reloads the page from the backend, which is still up |
| iOS ends the app | The BEAM ends with it; opening the app starts a new one |
| The BEAM halts (`System.stop/1`, a crash of the top supervisor) | The app ends with it: ERTS cannot be restarted inside the same process |

Whatever lived only in the page is gone after a reload: the open document, the
view, unsaved edits. Keep that state with the backend, under
`ExTauri.Paths.config_dir/0`, and hand it back when the page loads.

A listening socket iOS reclaimed while the app was suspended never accepts
again, and the BEAM is not told: the window stays on "connecting" until the app
is quit. `ExTauri.Resume`, which ex_tauri starts for you, notices the resume
and restarts every listener it watches that no longer accepts.
`ExTauri.Native` watches its own; watch your HTTP endpoint once your
supervisor is up, and reconnect what else needs it:

```elixir
# application.ex
{:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

ExTauri.Resume.watch(:http, Application.fetch_env!(:ex_tauri, :port), fn ->
  ExTauri.Resume.restart_child(MyApp.Supervisor, MyApp.Router)
end)

ExTauri.Resume.on_resume(:links, fn _suspended_ms -> MyApp.reconnect() end)
{:ok, sup}
```

## Native plugins

Some of iOS is only reachable from Swift: Bluetooth, Multipeer Connectivity,
HealthKit, the camera. A native plugin brings it to your Elixir code:

```bash
mix ex_tauri.ios plugin near-radio
```

writes `src-tauri/plugins/near-radio`, a Tauri plugin crate with a Swift package,
and registers it in the shell. `mix ex_tauri.ios init` registers every plugin in
`src-tauri/plugins/*` (and every crate in `config :ex_tauri, :ios_plugins`, such
as `{"tauri-plugin-haptics", "2"}`) in the generated `lib.rs` and in an iOS-only
table of `Cargo.toml`: you never edit `lib.rs`, and `init` can keep regenerating it.

The plugin's Swift class talks to the BEAM on a channel named after it, through
`ExTauri.Native`:

```swift
// src-tauri/plugins/near-radio/ios/Sources/NearRadioPlugin.swift
let native = ExTauriNative(channel: "near-radio")

native.on { message in /* from ExTauri.Native.send/2 */ }
native.onConnect = { native.send(["hello": "from Swift"]) }
native.start()
```

```elixir
# application.ex
children = [ExTauri.ShutdownManager, ExTauri.Native, ...]

ExTauri.Native.subscribe("near-radio")
# {:ex_tauri_native, "near-radio", :connected}
# {:ex_tauri_native, "near-radio", %{"hello" => "from Swift"}}
ExTauri.Native.send("near-radio", %{"op" => "start"})
```

Messages are JSON. `ExTauri.Native` listens on loopback at a free port and writes
the port and a token, new at every launch, to
`Library/Application Support/ex_tauri/native.json` inside the app's container
(mode 600); `ExTauriNative.swift` reads them and must present the token first, so
no other app can connect. The BEAM starts after the app, and the Swift side
reconnects on its own. `ExTauriNative.swift` belongs to ex_tauri: `init` rewrites
it to match the version in use. Run `mix ex_tauri.ios init` before
`mix ex_tauri.ios plugin`.

Native plugins work in `mix ex_tauri.ios run` and `device` builds only, not under
`mix ex_tauri.ios dev`: there the BEAM runs on the Mac, `ExTauri.Native` is
`:ignore`d (`send/2` answers `{:error, :not_connected}`), and the handoff file it
would write is under the Mac's home, not in the simulator app's container where
`ExTauriNative.swift` looks for it.

Add the usage descriptions your frameworks need (`NSBluetoothAlwaysUsageDescription`,
`NSBonjourServices`, ...) to `src-tauri/Info.ios.plist`, which Tauri merges into
the app's `Info.plist`.

## What the shell does for you

ex_tauri registers its own iOS plugin in every app (`priv/ios_shell`, used from the
dependency): the web view's keyboard behaves like an app's.

| `config :ex_tauri, :ios` | Default | |
|---|---|---|
| `form_accessory_bar` | `false` | WKWebView's previous / next / done bar above the keyboard |
| `dismiss_keyboard_on_swipe` | `true` | a downward swipe puts the keyboard away, as in Messages |
| `app_like_page` | `true` | every page gets a non-zooming, full-screen viewport and touch CSS (no double-tap zoom, no tap flash, no text inflation) before its own code runs |
| `keyboard_resize` | `true` | the web view shrinks to the space above the keyboard, so a layout at `100%` / `100dvh` keeps its text field in sight; the page gets `<html data-keyboard="open">` and `--ex-tauri-keyboard-height` (hide a tab bar with `html[data-keyboard="open"] nav { display: none }`) |

Rerun `mix ex_tauri.ios init` after changing them (they are written to
`tauri.ios.conf.json`). Something every app needs belongs here, in ex_tauri, not in
each app's plugins.

## Rules for a mobile app

Each of these broke on a real device; most never show in the simulator.
`mix ex_tauri.ios doctor` checks the ones it can (and `init`, `run` and `device`
run it): a missing permission key stops `run` and `device`, the rest warn.

- **Never edit the generated `lib.rs` or `build.rs`**: native code goes in a plugin
  (`mix ex_tauri.ios plugin`), third-party Tauri plugins in
  `config :ex_tauri, :ios_plugins`.
- **No processes, no foreign NIFs**: no `System.cmd/3` or ports; only OTP's crypto
  and asn1 NIFs.
- **Write only under `ExTauri.Paths`**: the container's root is read-only on a
  device (the simulator's is not).
- **Keep state in the backend**: the page may be reloaded at any time.
- **Expect to be frozen in the background**, BEAM included: watch every listener
  with `ExTauri.Resume.watch/3` (your HTTP endpoint first, see
  [Sleep, suspension, and crashes](#sleep-suspension-and-crashes)) and reconnect
  in `ExTauri.Resume.on_resume/2`.
- **Declare permissions in `src-tauri/Info.ios.plist`**: Local Network, Bonjour
  services, Bluetooth, background modes.
- **Unicast on the LAN**: broadcast and multicast need an Apple entitlement.
- **No page zoom**: `maximum-scale=1, user-scalable=no` and
  `touch-action: manipulation`; inputs at 16px or larger.
- **Distribution is opt-in and full trust**: start it at runtime (there is no epmd;
  `dist_listen: false`, or a `:kernel` `epmd_module` that derives ports from node
  names); `ExTauri` places a cookie file where OTP can create none; never connect
  untrusted nodes.

## Debugging on a device

iOS forwards none of the BEAM's output from a device. Log to a file under
`ExTauri.Paths.config_dir/0` (`:logger.add_handler/3` with `:logger_std_h`) and
copy it off:

```bash
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier <bundle id> \
  --source "Library/Application Support/<app>/app.log" --destination ./device.log
```

`xcrun devicectl device info files` (same `--domain-*` options) lists what is there.

## Designing for iPhone and iPad

The window is a WKWebView, so this is responsive web design with a few
iOS-specific details. In your root layout:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover">
```

`viewport-fit=cover` lets the page draw under the notch and home indicator, and
`maximum-scale=1, user-scalable=no` stops the page zooming like a document (add
`html { touch-action: manipulation; }` for double taps). Pad for the notch and home
indicator with the safe-area insets:

```css
body {
  padding: env(safe-area-inset-top) env(safe-area-inset-right)
           env(safe-area-inset-bottom) env(safe-area-inset-left);
  min-height: 100dvh; /* dvh: the visible height, toolbars excluded */
}
```

Breakpoints that match the devices:

```css
/* iPhone, portrait: one column, a bottom bar instead of a sidebar */
@media (max-width: 599px) { … }

/* iPad portrait, iPhone landscape, iPad split-screen */
@media (min-width: 600px) and (max-width: 1023px) { … }

/* iPad landscape, Stage Manager windows, the desktop */
@media (min-width: 1024px) { … }
```

Prefer capability queries to device guesses — an iPad with a trackpad has a
fine pointer and hover, an iPad without one does not:

```css
@media (hover: none) and (pointer: coarse) {
  button, [role="button"] { min-height: 44px; } /* Apple's touch target */
  .shortcut-hint { display: none; }             /* no ⌘K without a keyboard */
}
```

With `mix ex_tauri.ios dev` running, every change reloads in the simulator;
`--device` switches between an iPhone and an iPad.

## Troubleshooting

**"Xcode's iOS simulator SDK is X, but the newest installed simulator runtime
is Y."** `cargo tauri ios build` refuses to build when Xcode's simulator SDK
is newer than every installed runtime, although the app runs fine on the older
one. Install the matching runtime (`xcodebuild -downloadPlatform iOS`, several
GB), or pass `--allow-older-runtime`: the task puts an `xcrun` wrapper on
`PATH` for the build that reports the installed runtime as the SDK's version to
that one query, and changes nothing else.

**The build fails with `no such command: tauri`.** Xcode's build phase runs
`cargo tauri ios xcode-script`. The task puts the Tauri CLI that
`mix ex_tauri.install` set up on `PATH`; if you build from Xcode directly, add
`_build/_tauri/bin` to `PATH` yourself.

**"Command PhaseScriptExecution failed" when building from Xcode.** Its "Build
Rust Code" phase only works while `cargo tauri ios build` (or `dev`) is
running. Build with `mix ex_tauri.ios`, or run `cargo tauri ios build --open`
and use Xcode's Run while it waits.

**"Operation not permitted" reading `.tauri/cli-options-server.json`.** Xcode
turned user script sandboxing on (Xcode 27 does when it saves a project). The
task turns it back off before every build.

**"No signing team" / the device build fails to sign.** See
[Requirements](#requirements): an Apple ID in Xcode and its team ID in
`tauri.ios.conf.json`.

**The app installs but does not open.** A locked device refuses to launch
apps; unlock it. The first time, trust your developer profile in Settings >
General > VPN & Device Management. With a free Personal Team the app stops
opening after 7 days: run `mix ex_tauri.ios device` again.

**"this build has no Erlang runtime linked in".** The app was built without a
staged runtime (`mix ex_tauri.ios dev`, or a build from Xcode): build it with
`run` or `device`.

**The backend never answers.** Run with `--console` to see its output. A
release whose `:steps` add `&Burrito.wrap/1` unconditionally cannot be packed
by ampoule — make it conditional on `BURRITO_SKIP`, which the packager sets:

```elixir
steps: [:assemble] ++ if(System.get_env("BURRITO_SKIP") == "true", do: [], else: [&Burrito.wrap/1])
```
