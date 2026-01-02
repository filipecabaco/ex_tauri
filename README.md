# ExTauri

> Warning: Still a Proof of Concept with a lot of bad code!
> Wrapper around Tauri to enable the development of Phoenix Desktop applications

![example.gif](example.gif)

## Acknowledgements

- [Tauri App](tauri.app) for building it and providing a ton of support to find the right way to build the PoC
- [Digit / Doawoo](https://twitter.com/doawoo) for [Burrito](https://github.com/burrito-elixir/burrito) which enables us to build the binary to be used as a sidecar
- [Kevin Pan / Feng19](https://twitter.com/kevin52069370) for their example that heavily inspired the approach taken with their [phx_new_desktop](https://github.com/feng19/phx_new_desktop) repository
- [yos](https://twitter.com/r8code) for a [great discussion](https://twitter.com/r8code/status/1692573451767394313?s=20) and bringing Feng19 example into the mix (no pun intended)
- [Phoenix Framework Tailwind](https://github.com/phoenixframework/tailwind) which was a big inspiration on the approach to be taken when it came to install an outside package and use it within an Elixir project

## How it works

### Tauri.install

- Using Rusts cargo install, installs [Tauri](tauri.app) in your local dependencies
- Runs `tauri init` with the given configuration to create your `src-tauri` folder in your project root
- Overrides `Cargo.toml` since original [Tauri](tauri.app) depends on installation folders which made it trickier
- Moves `build.rs` into `src-tauri/src` due to an error during development
- Setups the required sidecars in `src-tauri/tauri.conf.json`

### Tauri.run

- Turns off `TAURI_SKIP_DEVSERVER_CHECK` which was blocking the [Tauri](tauri.app) code from running `main.rs`
- Checks if the project has a [Burrito](https://github.com/burrito-elixir/burrito) release configured
- Wraps the Phoenix application using [Burrito](https://github.com/burrito-elixir/burrito)
- Renames the output from [Burrito](https://github.com/burrito-elixir/burrito) to be compatible with Tauri's way of calling a sidecar
- Runs `tauri` and passes the arguments into [Tauri](tauri.app)

## Installation

### Requirements

- Zig (0.10.0)
- Rust

### Getting your application ready

For reference please check the [example](/example) folder in this repository

- Add dependency

```elixir
def deps do
  [
    {:ex_tauri, git: "https://github.com/filipecabaco/ex_tauri.git"}
  ]
end
```

- Add configuration

```elixir
# The version can be any 2.x version - the library automatically extracts
# the major version for CLI and plugin installations to avoid version mismatches
config :ex_tauri, version: "2.5.1", app_name: "Example Desktop", host: "localhost", port: 4000
```

- Add burrito release

```elixir
  def project do
    [
      app: :example_desktop,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end
  # ...
  defp releases do
    [
      desktop: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            # At the moment we still need this really specific names
            "aarch64-apple-darwin": [os: :darwin, cpu: :aarch64]
           ]
        ]
      ]
    ]
  end
```

- Add `:inets` and other `extra_applications` you might need since burrito needs to be aware of them

```elixir
  def application do
    [
      mod: {ExampleDesktop.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets]
    ]
  end
```

- Extra: Have a way to start up your repos during startup:

```elixir
defmodule ExampleDesktop.Starter do
  alias ExampleDesktop.Repo

  def run() do
    Application.ensure_all_started(:ecto_sql)

    Repo.__adapter__().storage_up(Repo.config())
    Ecto.Migrator.run(Repo, :up, all: true)
  end
end
```

- Check your runtime.exs, there's a lot of environment variables that you might need to build your server

- Setup tauri by running `mix ex_tauri.install`

## Running

### Development Mode (Recommended)
Run your app in development mode with hot reloading:
```bash
cd your_project
mix ex_tauri dev
```

### Building for Distribution
Build a distributable package (creates both `.app` and `.dmg` on macOS):
```bash
cd your_project
mix ex_tauri build
```

**Note**: DMG creation requires Xcode Command Line Tools. If you encounter DMG build errors, see the troubleshooting section below.

## Troubleshooting

### Build Error: "failed to bundle project error running bundle_dmg.sh"

**Problem**: When running `mix ex_tauri build`, you get errors like:
- "No space left on device" (even though you have disk space)
- DMG creation fails

**Root Cause**: Burrito-wrapped Phoenix apps are very large (include entire Erlang runtime), and the default DMG size is too small.

**Solution**: Configure a larger DMG size in `src-tauri/tauri.conf.json`:

```json
{
  "bundle": {
    "macOS": {
      "dmg": {
        "size": 1000000
      }
    }
  }
}
```

The `size` is in KB. 1000000 KB = ~1 GB, which should be sufficient for most Burrito apps.

**Alternative Solutions**:

1. **Build without DMG** (only create .app bundle):
   ```json
   {
     "bundle": {
       "targets": ["app"]
     }
   }
   ```

2. **Check actual app size** to set appropriate DMG size:
   ```bash
   du -sh src-tauri/target/release/bundle/macos/*.app
   # Set dmg.size to at least 1.5x the app size (in KB)
   ```

The `.app` bundle is created successfully at `src-tauri/target/release/bundle/macos/YourApp.app` even if DMG creation fails.

**Reference**: See [Tauri v2 DMG Documentation](https://v2.tauri.app/distribute/dmg/) for more configuration options.

### Build Error: "Could not write configuration file because it has invalid terms"

**Problem**: This error occurs when Burrito tries to serialize development configuration that contains regexes (like Phoenix's `live_reload` patterns). Regexes cannot be serialized in Elixir releases.

**Solution**: The library now automatically builds releases with `MIX_ENV=prod`, which excludes development configuration. No action needed on your part.

**How it works**: When you run `mix ex_tauri build`, the library:
1. Sets `MIX_ENV=prod` before creating the release
2. This ensures `config/dev.exs` is not included in the release
3. Only `config/prod.exs` and `config/runtime.exs` are used
4. After the release is created, the original MIX_ENV is restored

### Installation Error: "could not find tauri-cli in registry"

This has been fixed in version 2.x. The library now automatically uses semver ranges for all Tauri dependencies. Make sure you're using the latest version.

### Runtime Error: "You must provide a :database to the database"

**Problem**: When running `mix ex_tauri dev`, you get Exqlite connection errors about missing database configuration.

**Solution**: Add database configuration to your `config/runtime.exs`:

```elixir
# Configure the database at runtime
database_path =
  System.get_env("DATABASE_PATH") ||
    Path.join([System.user_home!(), ".your_app", "your_app.db"])

database_path |> Path.dirname() |> File.mkdir_p!()

config :your_app, YourApp.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")
```

**Why**: Burrito-wrapped apps use production environment even in dev mode, so dev.exs database configs aren't loaded. Runtime configuration ensures the database path works in any environment.

### Runtime Error: "could not warm up static assets"

**Problem**: Error about missing `cache_manifest.json` when running the app.

**Solution**: Comment out or remove the `cache_static_manifest` configuration in your `config/prod.exs`:

```elixir
# Comment this out:
# config :your_app, YourAppWeb.Endpoint,
#   cache_static_manifest: "priv/static/cache_manifest.json"
```

**Why**: The cache manifest is only needed for production deployments where assets are pre-compiled. In development and desktop apps, it's not required.
