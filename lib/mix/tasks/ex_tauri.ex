defmodule Mix.Tasks.ExTauri do
  @moduledoc """
  Invokes Tauri CLI commands directly (advanced usage).

  This is a generic task for running arbitrary Tauri CLI commands. For common
  operations, prefer using the dedicated Mix tasks which provide better
  documentation and option handling:

  - `mix ex_tauri.install` - Install and configure Tauri
  - `mix ex_tauri.dev` - Run in development mode
  - `mix ex_tauri.build` - Build for production
  - `mix ex_tauri.info` - Show project information
  - `mix ex_tauri.icon` - Generate application icons
  - `mix ex_tauri.signer` - Manage code signing

  ## Usage

      $ mix ex_tauri <command> [args...]

  ## Common Commands

  If you need to use Tauri commands that don't have dedicated Mix tasks:

      # Manage plugins
      $ mix ex_tauri plugin <subcommand>

      # Add a Tauri plugin
      $ mix ex_tauri add <plugin-name>

      # Mobile development (requires mobile setup)
      $ mix ex_tauri android <subcommand>
      $ mix ex_tauri ios <subcommand>

      # Generate shell completions
      $ mix ex_tauri completions <shell>

      # Migrate between Tauri versions
      $ mix ex_tauri migrate

  ## Examples

      # Add the dialog plugin
      $ mix ex_tauri add dialog

      # Initialize Android development
      $ mix ex_tauri android init

      # Generate completions for bash
      $ mix ex_tauri completions bash

  ## Note

  This task builds your Elixir release and runs the Tauri CLI with the
  provided arguments. For most use cases, the dedicated tasks provide a
  better experience with proper option parsing and documentation.

  Run `mix help ex_tauri.<command>` for detailed help on specific tasks.

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Invokes Tauri CLI commands (use dedicated tasks for common operations)"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    ExTauri.run(args)
  end
end
