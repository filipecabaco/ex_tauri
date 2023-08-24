# Tauri

Collection of tools to help you build a Liveview powered

## Installation
### Requirements
* Zig (0.10.0)
* Rust

### Getting your application ready
* Add dependency
```elixir
def deps do
  [
    {:tauri, path: "/Users/filipecabaco/workspace/tauri"}
  ]
end
```
* Add configuration
```elixir
config :tauri, version: "1.4.0", app_name: "Example Desktop", host: "localhost", port: 4000
```
* Add burrito release
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
* Add `:inets` and other `extra_applications` you might need since burrito needs to be aware of them
```elixir
  def application do
    [
      mod: {ExampleDesktop.Application, []},
      extra_applications: [:logger, :runtime_tools, :inets]
    ]
  end
```
Extra:
Have a way to start up your repos during startup:
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
* Check your runtime.exs, there's a lot of environment variables that you might need to build your server

* Setup tauri by running `mix tauri.install`

* Run tauri in development mode with `mix tauri dev`


