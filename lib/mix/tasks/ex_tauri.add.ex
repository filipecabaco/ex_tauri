defmodule Mix.Tasks.ExTauri.Add do
  @moduledoc """
  Adds Tauri plugins to your project so the matching Elixir APIs work.

  Each plugin normally requires three coordinated edits to `src-tauri/`:
  a crate in `Cargo.toml`, a `.plugin(...)` registration in `src/main.rs`,
  and permissions in `capabilities/default.json`. This task performs all
  three for you, and is safe to re-run (already-installed plugins are
  skipped).

  ## Usage

      $ mix ex_tauri.add PLUGIN [PLUGIN...]

  ## Examples

      # Enable native dialogs and filesystem access from LiveView
      $ mix ex_tauri.add dialog fs

      # Enable everything commonly used
      $ mix ex_tauri.add dialog fs clipboard os global-shortcut autostart process

  ## Available plugins

  | Plugin            | Elixir API               | Enables                               |
  |-------------------|--------------------------|----------------------------------------|
  | `dialog`          | `ExTauri.Dialog`         | Native file/message dialogs            |
  | `fs`              | `ExTauri.Filesystem`     | Filesystem access outside the sandbox  |
  | `clipboard`       | `ExTauri.Clipboard`      | Read/write the system clipboard        |
  | `os`              | `ExTauri.OS`             | OS platform/arch/locale info           |
  | `global-shortcut` | `ExTauri.GlobalShortcut` | App-wide keyboard shortcuts            |
  | `autostart`       | `ExTauri.Autostart`      | Launch at login                        |
  | `process`         | `ExTauri.App`            | Exit/relaunch the app                  |
  | `updater`         | `ExTauri.Updater`        | Check for and install updates          |
  | `deep-link`       | `ExTauri.Event`          | Handle `myapp://` URLs                 |
  | `window`          | `ExTauri.Window`         | Runtime window management permissions  |

  After adding a plugin, rebuild with `mix ex_tauri.dev` (the Rust side
  recompiles automatically).
  """

  @shortdoc "Adds Tauri plugins (Cargo dep, Rust init, capabilities)"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run([]) do
    Mix.raise("""
    No plugin given. Usage:

        mix ex_tauri.add PLUGIN [PLUGIN...]

    Available plugins: #{Enum.join(ExTauri.Plugins.known(), ", ")}
    """)
  end

  def run(argv) do
    installed = ExTauri.Plugins.add!(argv)

    for {name, plugin} <- installed do
      Mix.shell().info("* #{name} — ready. Use #{plugin.api} from your LiveView.")

      if note = plugin[:note] do
        Mix.shell().info("\n" <> note)
      end
    end

    Mix.shell().info("""

    Done. Rebuild with `mix ex_tauri.dev` to compile the new Rust plugins.
    """)
  end
end
