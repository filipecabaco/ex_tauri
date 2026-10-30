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
| The app goes to the background, or the device locks | iOS suspends the whole app, BEAM included; it carries on when the app comes back. Connections may have dropped meanwhile: reconnect on failure |
| iOS reclaims the suspended app's web content | WebKit reloads the page from the backend, which is still up |
| iOS ends the app | The BEAM ends with it; opening the app starts a new one |
| The BEAM halts (`System.stop/1`, a crash of the top supervisor) | The app ends with it: ERTS cannot be restarted inside the same process |

Whatever lived only in the page is gone after a reload: the open document, the
view, unsaved edits. Keep that state with the backend, under
`ExTauri.Paths.config_dir/0`, and hand it back when the page loads.

## Designing for iPhone and iPad

The window is a WKWebView, so this is responsive web design with a few
iOS-specific details. In your root layout:

```html
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
```

`viewport-fit=cover` lets the page draw under the notch and home indicator; pad
for them with the safe-area insets:

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
