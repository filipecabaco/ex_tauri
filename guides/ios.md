# iPhone and iPad

`mix ex_tauri.ios` runs your app on iPhone and iPad — today in the iOS
simulator — with the same Elixir backend and the same UI as the desktop build.

```bash
mix ex_tauri.ios init    # once: prepare src-tauri for iOS
mix ex_tauri.ios dev     # the simulator on your dev server, live reload
mix ex_tauri.ios run     # the packed backend, as it would ship
```

> #### Simulator only, for now {: .warning}
>
> On iOS the app starts its Elixir backend as a child process, packed by
> [ampoule](https://github.com/filipecabaco/ampoule). The simulator allows
> that; a real device forbids both starting a process and the executable
> memory ampoule's engine maps, and the shell says so if installed on one.
> Running the backend *inside* the app process instead is the path to devices
> — see [What this opens up](#what-this-opens-up).

## Requirements

- Xcode with an iOS simulator runtime (`xcrun simctl list runtimes`)
- The Rust iOS targets: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`
- For `run`: [ampoule](https://github.com/filipecabaco/ampoule/releases) on
  `PATH` (or `config :ex_tauri, :ampoule_path, "..."`) and **OTP 28**, the OTP
  of ampoule's runtime. `dev` needs neither.

## Preparing the project

`mix ex_tauri.ios init` touches four files and leaves the desktop build alone:

| File | What changes |
|------|--------------|
| `src-tauri/src/lib.rs` | The iOS shell. Replaces the stub `cargo tauri init` leaves there; refuses a `lib.rs` with code of its own unless `--force`. Everything in it is `#[cfg(mobile)]`, so the desktop crate compiles past it. |
| `src-tauri/Cargo.toml` | A `[lib]` the iOS build links, and `tauri-plugin-single-instance` moved to a desktop-only table (only `main.rs` uses it, and it does not build for iOS). |
| `src-tauri/tauri.ios.conf.json` | Merged over `tauri.conf.json` for iOS: the backend as a resource instead of a sidecar, a bundled loading page, an identifier iOS accepts. |
| `src-tauri/mobile/index.html` | The loading page. |

It then runs `cargo tauri ios init` to generate the Xcode project in
`src-tauri/gen/apple`. Rerunning `init` is safe; it regenerates only what it
wrote.

## Running it

### `mix ex_tauri.ios dev` — while you build the UI

Builds the shell without a backend, launches it pointed at
`http://<:host>:<:port>`, and runs your `:dev_command` in the foreground. The
simulator shares the Mac's network, so the window loads your dev server and
**live reload works** — edit CSS, see the iPhone update.

### `mix ex_tauri.ios run` — as it would ship

Packs your release with ampoule for the Mac's architecture (the simulator runs
Mac binaries), bundles it into the app, installs, and launches. The app starts
the backend as its own child process, bound to `127.0.0.1` on a free port, and
points its window at it. Nothing else is involved: no dev server, no network.

### Options

- `--device NAME|UDID` — which simulator. Defaults to one already booted, else
  the first iPad. Try `--device "iPhone 17 Pro"` for the phone layout.
- `--console` — stay attached and print the app's output.
- `--allow-older-runtime` — see [Troubleshooting](#troubleshooting).

The simulator window is **Simulator.app**, or on Xcode 27 **DeviceHub**
(`/Applications/Xcode.app/Contents/Applications/DeviceHub.app`); the task opens
whichever is installed.

## How the backend runs

```
iOS app (Tauri shell, src-tauri/src/lib.rs)
  │  spawns, holds stdin open
  ▼
ampoule binary  ── one file: your release + the BEAM, compiled to WebAssembly
  │  serves your UI on 127.0.0.1:<free port>
  ▼
WKWebView  ── loads it, LiveView socket included
```

ampoule shows the backend only its own release, a private `/tmp`, and what the
shell mounts. The shell mounts the app's sandbox container and passes:

| Variable | Read by | Why |
|----------|---------|-----|
| `EX_TAURI_HOME` | `ExTauri.Paths` | ampoule's own `HOME` is its private `/tmp`, deleted on exit |
| `EX_TAURI_HOST_OS=ios` | `ExTauri.Paths` | the guest reports Linux on every host |
| `EX_TAURI_HEARTBEAT_STDIN=1` | `ExTauri.ShutdownManager` | a Unix socket path in the container is too long; stdin closing stops the backend instead |
| `PORT`, `SECRET_KEY_BASE`, `:sidecar_env` | your app | as on the desktop |

### Where to keep files

Use `ExTauri.Paths`, which resolves inside the app's container on iOS:

- `ExTauri.Paths.data_dir/0`, `config_dir/0`, `cache_dir/0` — app state
- `ExTauri.Paths.documents_dir/0` — files the user owns; on iOS this is the
  folder the Files app shows for your app

Code that reads `System.user_home!/0` or `XDG_*` directly gets ampoule's
private `/tmp` and loses its data when the app stops. For an app with its own
setting, pick the root in `config/runtime.exs`:

```elixir
if System.get_env("EX_TAURI_HOST_OS") == "ios" do
  config :my_app, root: ExTauri.Paths.documents_dir()
end
```

### What behaves differently

- **No desktop channel.** `ExTauri.Desktop` (tray, server-side notifications)
  answers `{:error, :not_connected}`.
- **No host programs.** `System.cmd/3` is refused by ampoule unless allowed —
  e.g. a "move to Trash" that shells out fails with an error.
- **No orphan sweep.** `ExTauri.Sidecar.Orphan` needs `ps`; it degrades to
  "cannot tell". The stdin heartbeat is what stops the backend.

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

**The backend never answers.** Run with `--console` to see its output. A
release whose `:steps` add `&Burrito.wrap/1` unconditionally cannot be packed
by ampoule — make it conditional on `BURRITO_SKIP`, which the packager sets:

```elixir
steps: [:assemble] ++ if(System.get_env("BURRITO_SKIP") == "true", do: [], else: [&Burrito.wrap/1])
```

## What this opens up

Packing the BEAM as one WebAssembly-backed executable is what makes the
backend portable enough to put inside a phone app at all. What exists today,
and what it points at:

- **Today:** desktop sidecars with no unpack step and OTP 28
  (`config :ex_tauri, :packager, :ampoule`), and iPhone/iPad in the simulator.
- **Next — real devices:** run ampoule as a library inside the app process
  instead of a child process, with wasmtime's Pulley interpreter where iOS
  forbids executable memory. The shell's contract (loopback port, stdin-style
  liveness, mounted container) stays the same.
- **Android:** the same in-process route; Android allows the executable memory
  ampoule already uses.
- **One codebase, every screen:** a LiveView app that is a desktop window, a
  tablet app and a phone app, with the layout switched by media queries rather
  than by separate frontends.
