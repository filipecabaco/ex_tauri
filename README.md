# ExTauri

**Build native desktop applications with Phoenix and Elixir.**

ExTauri wraps [Tauri](https://tauri.app) to enable Phoenix LiveView applications to run as native desktop apps on macOS, Windows, and Linux.

![example.gif](example.gif)

## Features

- **Phoenix LiveView as Desktop Apps** — Turn your Phoenix app into a native desktop application
- **Desktop APIs from Elixir** — Notifications, dialogs, clipboard, filesystem, window management, global shortcuts, and more — all driven from your LiveView, no JavaScript required
- **One-Command Plugin Setup** — `mix ex_tauri.add dialog fs` wires the Rust side for you (Cargo dep, plugin registration, permissions)
- **Native Events in LiveView** — Subscribe to drag-and-drop, focus, or custom Rust events and handle them in `handle_event/3`
- **Single Binary Distribution** — Uses [Burrito](https://github.com/burrito-elixir/burrito) to bundle everything into one executable
- **Hot Reload in Dev Mode** — Full Phoenix development experience with live reload
- **Graceful Shutdown** — Heartbeat-based mechanism ensures clean shutdown on CMD+Q, crashes, or force-quit
- **Automated Setup** — Uses [Igniter](https://hexdocs.pm/igniter) for safe, AST-aware project configuration
- **Cross-Platform** — Build for macOS, Windows, and Linux

## Prerequisites

- **Elixir** >= 1.15 with **OTP 27** (OTP 28 not yet supported due to Burrito ERTS availability)
- **Rust** — [Install via rustup](https://www.rust-lang.org/tools/install)
- **Platform dependencies** — see [Tauri prerequisites](https://v2.tauri.app/start/prerequisites/)

> **Note:** Zig is only required if you use Burrito for cross-compilation. For same-platform builds, Rust alone is sufficient.

## Getting Started

### 1. Add ExTauri to your Phoenix project

```elixir
# mix.exs
def deps do
  [
    {:ex_tauri, git: "https://github.com/filipecabaco/ex_tauri.git"}
  ]
end
```

### 2. Install and set up

```bash
mix deps.get
mix ex_tauri.install
```

That's it! `mix ex_tauri.install` handles everything automatically:

- **Config** — Sets sensible defaults for `app_name`, `host`, `port`, and `version` in `config/config.exs`
- **Tauri CLI** — Installs via Cargo
- **Project structure** — Scaffolds `src-tauri/` with Rust code, config, and capabilities
- **Supervision tree** — Adds `ExTauri.ShutdownManager` to your application (via Igniter)
- **Release config** — Adds a `:desktop` release to `mix.exs` (via Igniter)
- **JS hook** — Generates `assets/vendor/ex_tauri.js` and auto-injects the import and hook registration into `assets/js/app.js`
- **Layout** — Auto-injects the `<div id="tauri-bridge">` element into your root layout

### 3. Run in development

```bash
mix ex_tauri.dev
```

This starts your Phoenix app as a native desktop window with full hot-reload support.

> **Tip:** Review the generated config in `config/config.exs` to customize your app name, port, or window settings.

## Building for Production

### 1. Add Burrito wrapping

Update the `:desktop` release in your `mix.exs` to include Burrito:

```elixir
# mix.exs
def project do
  [
    # ... existing config
    releases: [
      desktop: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            "aarch64-apple-darwin": [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  ]
end
```

### 2. Add required applications

```elixir
# mix.exs
def application do
  [
    mod: {MyApp.Application, []},
    extra_applications: [:logger, :runtime_tools, :inets]
  ]
end
```

### 3. Build

```bash
mix ex_tauri.build
```

Your app bundle will be at `src-tauri/target/release/bundle/` with platform-specific packages:
- **macOS:** `.app` and `.dmg`
- **Linux:** `.deb` and `.appimage`
- **Windows:** `.msi` and `.exe`

## Mix Tasks

| Task | Description |
|------|-------------|
| `mix ex_tauri.install` | Set up Tauri in your project (one-time) |
| `mix ex_tauri.add` | Add Tauri plugins (dialogs, filesystem, shortcuts, ...) |
| `mix ex_tauri.dev` | Run in development mode with hot-reload |
| `mix ex_tauri.build` | Build for production |

Run `mix help ex_tauri.<task>` for detailed options.

## Using Desktop APIs

ExTauri provides Elixir modules for desktop features, all driven from your
LiveView. The JS bridge uses Tauri's global API, so **no npm packages are
required** — a stock Phoenix esbuild setup just works.

### Included by default

These work out of the box after `mix ex_tauri.install`:

- **`ExTauri.Notification`** — Native desktop notifications
- **`ExTauri.Shell`** — Open URLs, execute scoped commands
- **`ExTauri.Window`** — Runtime window management (minimize, fullscreen, title, size, ...)
- **`ExTauri.Event`** — Subscribe to native events (drag-and-drop, focus, custom Rust events)
- **`ExTauri.App`** — App name/version info

### One command away

These modules need a Tauri plugin on the Rust side. `mix ex_tauri.add` wires
everything (Cargo dependency, plugin registration, permissions):

| Module | Enable with |
|--------|-------------|
| **`ExTauri.Dialog`** — File open/save dialogs, message boxes | `mix ex_tauri.add dialog` |
| **`ExTauri.Clipboard`** — Read/write the system clipboard | `mix ex_tauri.add clipboard` |
| **`ExTauri.Filesystem`** — Read/write files outside the web sandbox | `mix ex_tauri.add fs` |
| **`ExTauri.OS`** — Query platform, architecture, locale | `mix ex_tauri.add os` |
| **`ExTauri.GlobalShortcut`** — App-wide keyboard shortcuts | `mix ex_tauri.add global-shortcut` |
| **`ExTauri.Autostart`** — Launch at login | `mix ex_tauri.add autostart` |
| **`ExTauri.App.exit/relaunch`** — App lifecycle control | `mix ex_tauri.add process` |
| **`ExTauri.Updater`** — Check for and install updates | `mix ex_tauri.add updater` |

### Example: sending a notification from LiveView

```elixir
def handle_event("notify", _params, socket) do
  socket = ExTauri.Notification.send(socket, "Saved!", body: "Your file was saved.")
  {:noreply, socket}
end

def handle_event("tauri_response", %{"command" => "notification", "status" => status}, socket) do
  {:noreply, assign(socket, :notification_status, status)}
end
```

### Example: opening a file dialog

First, install `tauri-plugin-dialog` (see `ExTauri.Dialog` docs), then:

```elixir
def handle_event("open_file", _params, socket) do
  socket = ExTauri.Dialog.open(socket,
    title: "Select a file",
    filters: [%{name: "Text", extensions: ["txt", "md"]}]
  )
  {:noreply, socket}
end

def handle_event("tauri_response", %{"command" => "dialog_open", "path" => path}, socket) do
  {:noreply, assign(socket, :selected_file, path)}
end
```

### Example: window management and drag-and-drop

```elixir
def mount(_params, _session, socket) do
  socket =
    if connected?(socket) do
      ExTauri.Event.subscribe(socket, "tauri://drag-drop")
    else
      socket
    end

  {:ok, socket}
end

# React to files dropped onto the window
def handle_event("tauri_event", %{"event" => "tauri://drag-drop", "payload" => %{"paths" => paths}}, socket) do
  {:noreply, assign(socket, :dropped_files, paths)}
end

# Update the native window title as app state changes
def handle_event("open_document", %{"name" => name}, socket) do
  {:noreply, ExTauri.Window.set_title(socket, "#{name} — MyApp")}
end
```

## How It Works

### Architecture

```
┌─────────────────────┐
│   Tauri Window       │  Native window (Rust/WebView)
│   ┌───────────────┐  │
│   │  Phoenix UI   │  │  Your LiveView app rendered in WebView
│   └───────────────┘  │
└─────────┬────────────┘
          │
          │  HTTP — serves your Phoenix UI to the WebView
          │  Unix Socket — heartbeat for lifecycle management
          │
┌─────────┴────────────┐
│   Phoenix Server     │  Your Elixir app (Burrito-wrapped sidecar)
│   (Sidecar Process)  │
└──────────────────────┘
```

Tauri launches your Phoenix app as a **sidecar process**. The WebView connects to Phoenix over HTTP to render your LiveView UI. A separate local socket carries heartbeat signals for lifecycle management.

### Heartbeat-Based Shutdown

ExTauri uses a local socket heartbeat to detect when the Tauri frontend exits:

1. `ShutdownManager` opens a listener:
   - **macOS/Linux:** a Unix domain socket at `<tmpdir>/tauri_heartbeat_<app_name>.sock`
   - **Windows:** a TCP socket on `127.0.0.1` with an OS-assigned port, published
     in `<tmpdir>/tauri_heartbeat_<app_name>.port` for the frontend to discover
2. The Rust frontend connects and sends a byte every **100ms**
3. `ShutdownManager` checks for heartbeats every **500ms**
4. If no heartbeat is received for **1500ms**, graceful shutdown begins
5. Phoenix closes connections, flushes logs, and exits cleanly

This works even when the app is force-quit, crashes, or is killed unexpectedly. The socket path is unique per application (based on `:app_name`) to prevent collisions. When you quit normally, the frontend stops heartbeating before waiting on the sidecar, so the same mechanism drives graceful shutdown on platforms without SIGTERM (Windows).

## Configuration

### Core Settings

```elixir
# config/config.exs
config :ex_tauri,
  version: "2.5.1",           # Tauri version (default: latest)
  app_name: "My App",         # Application name (required)
  host: "localhost",          # Phoenix host (required)
  port: 4000                  # Phoenix port (required)
```

### Window Settings

```elixir
config :ex_tauri,
  window_title: "My Window",  # Window title (defaults to app_name)
  fullscreen: false,          # Start in fullscreen
  width: 800,                 # Window width
  height: 600,                # Window height
  resize: true                # Allow window resize
```

### Advanced Settings

```elixir
config :ex_tauri,
  heartbeat_interval: 500,    # How often to check heartbeat (ms)
  heartbeat_timeout: 1500,    # Time without heartbeat before shutdown (ms)
  scheme: "http"              # URL scheme (http or https)
```

## Troubleshooting

### Rust/Cargo not found

```
Rust/Cargo is not installed or not in your PATH.
```

Install Rust via [rustup](https://www.rust-lang.org/tools/install):
```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

### Database configuration for desktop apps

Desktop apps need a local database path. Configure in `config/runtime.exs`:

```elixir
database_path =
  System.get_env("DATABASE_PATH") ||
    Path.join([ExTauri.Paths.data_dir(), "my_app.db"])

config :my_app, MyApp.Repo,
  database: database_path,
  pool_size: 5
```

### Running Ecto migrations in a desktop release

Desktop releases don't run `mix ecto.migrate`. Add a release module that
runs migrations on startup:

```elixir
# lib/my_app/release.ex
defmodule MyApp.Release do
  def migrate do
    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos, do: Application.fetch_env!(:my_app, :ecto_repos)
end
```

Then call it early in your `application.ex` startup:

```elixir
def start(_type, _args) do
  MyApp.Release.migrate()

  children = [
    MyApp.Repo,
    ExTauri.ShutdownManager,
    # ...
  ]
  # ...
end
```

### Static assets in production

Remove or comment out `cache_static_manifest` in `config/prod.exs` if you don't use `mix assets.deploy`:

```elixir
# config :my_app, MyAppWeb.Endpoint,
#   cache_static_manifest: "priv/static/cache_manifest.json"
```

### DMG build permission error (macOS)

```
execution error: Not authorised to send Apple events to Finder. (-1743)
```

Grant automation permissions: **System Settings** > **Privacy & Security** > **Automation** > enable **Finder** for your terminal app.

### Port already in use

If `mix ex_tauri.dev` hangs, check if another process is using the configured port:

```bash
lsof -i :4000
```

Kill the process or change the `:port` in your ExTauri config.

## Example

See the [example/](example/) directory for a complete working Phoenix desktop app with SQLite, LiveView, and Tailwind CSS.

## Acknowledgements

- [Tauri App](https://tauri.app) — For the amazing framework
- [Burrito](https://github.com/burrito-elixir/burrito) by Digit/Doawoo — For single-binary Elixir apps
- [Igniter](https://hexdocs.pm/igniter) — For safe, AST-aware code patching
- [phx_new_desktop](https://github.com/feng19/phx_new_desktop) by Kevin Pan/Feng19 — For inspiration

## License

MIT
