defmodule Mix.Tasks.ExTauri.Info do
  @moduledoc """
  Shows information about your Tauri project and environment.

  This task displays detailed information about your Tauri setup, including:
  - Tauri version and configuration
  - Platform and system information
  - Rust toolchain details
  - Project dependencies
  - Environment variables

  This is useful for debugging build issues and verifying your setup.

  ## Usage

      $ mix ex_tauri.info [OPTIONS]

  ## Options

    * `--interactive` - Enable interactive mode (prompts for additional info)
    * `--config <CONFIG>` - Use a custom tauri.conf.json file

  ## Examples

      # Show basic info
      $ mix ex_tauri.info

      # Show info with interactive mode
      $ mix ex_tauri.info --interactive

      # Show info for a specific config
      $ mix ex_tauri.info --config src-tauri/tauri.staging.conf.json

  ## Output

  The command will display:
  - Operating System and version
  - Node.js version (if applicable)
  - Rust version and toolchain
  - Tauri CLI version
  - Tauri configuration
  - Active feature flags
  - App and bundle information

  This information is helpful when:
  - Reporting issues to the ex_tauri project
  - Debugging build or runtime problems
  - Verifying your development environment
  - Checking cross-compilation setup

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Shows information about the Tauri project and environment"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    {opts, extra_args} = OptionParser.parse!(args,
      strict: [
        interactive: :boolean,
        config: :string
      ]
    )

    tauri_args = build_tauri_args(opts, extra_args)
    ExTauri.run_simple(["info" | tauri_args])
  end

  defp build_tauri_args(opts, extra_args) do
    args = []

    args = if opts[:interactive], do: args ++ ["--interactive"], else: args
    args = if opts[:config], do: args ++ ["--config", opts[:config]], else: args

    args ++ extra_args
  end
end
