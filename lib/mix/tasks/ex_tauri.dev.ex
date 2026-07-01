defmodule Mix.Tasks.ExTauri.Dev do
  @moduledoc """
  Runs the Tauri application in development mode with hot-reload.

  This task builds your Elixir release and starts the Tauri development server,
  which will open your application in a native window with hot-reload capabilities.

  The Phoenix dev server runs as a sidecar process managed by Tauri, so this command
  automatically skips waiting for the dev server (passes --no-dev-server-wait).

  ## Usage

      $ mix ex_tauri.dev [OPTIONS]

  ## Options

    * `--release` / `-r` - Run in release mode instead of debug mode
    * `--target <TARGET>` - Build for the specified target triple
    * `--runner <RUNNER>` - Use the specified runner for the binary
    * `--config <CONFIG>` - Use a custom tauri.conf.json file
    * `--port <PORT>` - Specify a custom port for the dev server
    * `--no-watch` - Disable file watching for hot-reload
    * `--features <FEATURES>` - Space or comma-separated list of features to activate
    * `--exit-on-panic` - Exit on panic

  ## Examples

      # Run in development mode (default)
      $ mix ex_tauri.dev

      # Run in release mode for better performance
      $ mix ex_tauri.dev --release

      # Run with specific Rust features
      $ mix ex_tauri.dev --features custom-protocol

      # Run with a custom config file
      $ mix ex_tauri.dev --config src-tauri/tauri.staging.conf.json

  ## Environment Setup

  Make sure you have:
  1. Installed Tauri via `mix ex_tauri.install`
  2. Configured your Phoenix server to run on the correct host and port
  3. Added ExTauri.ShutdownManager to your application supervision tree

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Runs Tauri in development mode with hot-reload"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @flag_specs [
    release: "--release",
    target: "--target",
    runner: "--runner",
    config: "--config",
    port: "--port",
    no_watch: "--no-watch",
    features: "--features",
    exit_on_panic: "--exit-on-panic"
  ]

  @impl true
  def run(args) do
    ExTauri.TaskHelpers.preflight_check!()

    {opts, extra_args} =
      OptionParser.parse!(args,
        strict: [
          release: :boolean,
          target: :string,
          runner: :string,
          config: :string,
          port: :integer,
          no_watch: :boolean,
          features: :string,
          exit_on_panic: :boolean
        ],
        aliases: [r: :release]
      )

    ExTauri.run_dev(["dev" | build_tauri_args(opts, extra_args)])
  end

  @doc false
  def build_tauri_args(opts, extra_args) do
    # --no-dev-server-wait is always passed: Tauri must not block waiting for a
    # dev server it doesn't manage (Phoenix is started separately).
    ["--no-dev-server-wait"] ++
      ExTauri.TaskHelpers.build_tauri_args(@flag_specs, opts, extra_args)
  end
end
