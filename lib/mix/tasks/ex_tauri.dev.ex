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

  @impl true
  def run(args) do
    {opts, extra_args} = OptionParser.parse!(args,
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
      aliases: [
        r: :release
      ]
    )

    tauri_args = build_tauri_args(opts, extra_args)
    ExTauri.run(["dev" | tauri_args])
  end

  defp build_tauri_args(opts, extra_args) do
    # Always skip waiting for dev server since Phoenix runs as a sidecar
    args = ["--no-dev-server-wait"]

    args = if opts[:release], do: args ++ ["--release"], else: args
    args = if opts[:target], do: args ++ ["--target", opts[:target]], else: args
    args = if opts[:runner], do: args ++ ["--runner", opts[:runner]], else: args
    args = if opts[:config], do: args ++ ["--config", opts[:config]], else: args
    args = if opts[:port], do: args ++ ["--port", to_string(opts[:port])], else: args
    args = if opts[:no_watch], do: args ++ ["--no-watch"], else: args
    args = if opts[:features], do: args ++ ["--features", opts[:features]], else: args
    args = if opts[:exit_on_panic], do: args ++ ["--exit-on-panic"], else: args

    args ++ extra_args
  end
end
