# ExTauri

**Build native desktop applications with Phoenix and Elixir.**

ExTauri wraps [Tauri](https://tauri.app) to enable Phoenix LiveView applications to run as native desktop apps on macOS, Windows, and Linux.

![example.gif](example.gif)

## Features

- 🚀 **Phoenix LiveView as Desktop Apps** - Turn your Phoenix app into a native desktop application
- 📦 **Single Binary Distribution** - Uses [Burrito](https://github.com/burrito-elixir/burrito) to bundle everything into one executable
- 🔄 **Hot Reload in Dev Mode** - Full Phoenix development experience with live reload
- 🎯 **Graceful Shutdown** - Heartbeat-based mechanism ensures clean shutdown on CMD+Q, crashes, or force-quit
- 🌍 **Cross-Platform** - Build for macOS, Windows, and Linux

## Quick Start

### Prerequisites

- [Rust](https://www.rust-lang.org/tools/install)
- [Zig 0.10.0](https://ziglang.org/download/)
- Elixir 1.14+

### Installation

1. **Add ExTauri to your Phoenix project:**

```elixir
# mix.exs
def deps do
  [
    {:ex_tauri, git: "https://github.com/filipecabaco/ex_tauri.git"}
  ]
end
```

2. **Configure ExTauri:**

```elixir
# config/config.exs
config :ex_tauri,
  version: "2.5.1",
  app_name: "My Desktop App",
  host: "localhost",
  port: 4000
```

3. **Add Burrito release:**

```elixir
# mix.exs
def project do
  [
    # ... existing config
    releases: releases()
  ]
end

defp releases do
  [
    desktop: [
      steps: [:assemble, &Burrito.wrap/1],
      burrito: [
        targets: [
          "aarch64-apple-darwin": [os: :darwin, cpu: :aarch64]
        ]
      ]
    ]
  ]
end
```

4. **Add required applications:**

```elixir
# mix.exs
def application do
  [
    mod: {MyApp.Application, []},
    extra_applications: [:logger, :runtime_tools, :inets]
  ]
end
```

5. **Add ExTauri.ShutdownManager to your supervision tree:**

```elixir
# lib/my_app/application.ex
def start(_type, _args) do
  children = [
    MyApp.Repo,
    {Phoenix.PubSub, name: MyApp.PubSub},
    MyAppWeb.Endpoint,
    ExTauri.ShutdownManager  # Add this at the bottom of the children list
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

6. **Install Tauri:**

```bash
mix deps.get
mix ex_tauri.install
```

### Usage

**Development** (with hot reload):
```bash
mix ex_tauri.dev
```

**Build for distribution**:
```bash
mix ex_tauri.build
```

Your app bundle will be at `src-tauri/target/release/bundle/macos/YourApp.app` (macOS) or equivalent for your platform.

### Available Mix Tasks

ExTauri provides dedicated Mix tasks for common operations:

- **`mix ex_tauri.install`** - Install and configure Tauri in your project
- **`mix ex_tauri.dev`** - Run in development mode with hot-reload
- **`mix ex_tauri.build`** - Build for production and create distributable packages
- **`mix ex_tauri.info`** - Show information about your Tauri project and environment
- **`mix ex_tauri.icon`** - Generate application icons from a source image
- **`mix ex_tauri.signer`** - Manage code signing for application updates

Each task provides detailed help and options:
```bash
mix help ex_tauri.dev
mix help ex_tauri.build
# etc.
```

For advanced usage or commands without dedicated tasks, use:
```bash
mix ex_tauri <command> [args...]
```

## How It Works

### Heartbeat-Based Shutdown

ExTauri uses a robust Unix domain socket heartbeat mechanism to ensure the Phoenix sidecar shuts down gracefully when the desktop app exits:

1. Elixir creates a Unix domain socket at `/tmp/tauri_heartbeat_<app_name>.sock`
2. Rust connects and sends a byte every 100ms
3. Elixir monitors heartbeats and checks every 100ms
4. If no heartbeat for 300ms (3 missed beats), graceful shutdown is initiated
5. Phoenix closes database connections, flushes logs, and exits cleanly

**Zero HTTP overhead** - Uses native Unix sockets (stdlib only, no dependencies!)

The socket path is unique per application (based on `:app_name` config) to prevent collisions when running multiple ExTauri apps simultaneously.

This works even when:
- The app is force-quit (CMD+Q on macOS)
- The app crashes unexpectedly
- The process is killed without cleanup

### Architecture

```
┌─────────────────┐
│  Tauri Window   │  ← Native UI (Rust)
│  (WebView)      │
└────────┬────────┘
         │ HTTP (for UI)
         │ Unix Socket (for heartbeat)
         ↓
┌─────────────────┐
│ Phoenix Server  │  ← Your Elixir App
│  (Sidecar)      │     (Burrito-wrapped)
│                 │     /tmp/tauri_heartbeat_<app>.sock
└─────────────────┘
```

## Configuration Options

```elixir
config :ex_tauri,
  version: "2.5.1",           # Tauri version
  app_name: "My App",         # Application name
  host: "localhost",          # Phoenix host
  port: 4000,                 # Phoenix port
  window_title: "My Window",  # Window title (defaults to app_name)
  fullscreen: false,          # Start in fullscreen
  width: 800,                 # Window width
  height: 600,                # Window height
  resize: true                # Allow window resize
```

## Common Issues

### Database Configuration

For desktop apps, configure your database in `config/runtime.exs`:

```elixir
database_path =
  System.get_env("DATABASE_PATH") ||
    Path.join([System.user_home!(), ".my_app", "my_app.db"])

File.mkdir_p!(Path.dirname(database_path))

config :my_app, MyApp.Repo,
  database: database_path,
  pool_size: 5
```

### Static Assets

Remove or comment out `cache_static_manifest` in `config/prod.exs`:

```elixir
# Not needed for desktop apps:
# config :my_app, MyAppWeb.Endpoint,
#   cache_static_manifest: "priv/static/cache_manifest.json"
```

### DMG Build Permission Issues (macOS)

When building DMGs on macOS, you may encounter an AppleScript permission error:

```
execution error: Not authorised to send Apple events to Finder. (-1743)
```

**This error prevents the DMG from being created** - the creation script uses AppleScript to configure the DMG appearance (backgrounds, icon positions), but requires Finder automation permissions.

**Solution: Grant Automation Permissions**

1. Open **System Settings** → **Privacy & Security** → **Automation**
2. Find your development environment (Terminal, iTerm2, VS Code, etc.)
3. Enable **Finder** access

After granting permissions, build normally:
```bash
cd example
mix ex_tauri.build
```

## Examples

Check the [example](/example) directory for a complete working Phoenix desktop application with:
- SQLite database (Ecto + Exqlite)
- Phoenix LiveView
- Tailwind CSS
- Notes CRUD interface

## Acknowledgements

- [Tauri App](https://tauri.app) - For the amazing framework and support
- [Burrito](https://github.com/burrito-elixir/burrito) by Digit/Doawoo - For enabling single-binary Elixir apps
- [phx_new_desktop](https://github.com/feng19/phx_new_desktop) by Kevin Pan/Feng19 - For inspiration
- [Phoenix Tailwind](https://github.com/phoenixframework/tailwind) - For the package installation approach

## License

MIT
