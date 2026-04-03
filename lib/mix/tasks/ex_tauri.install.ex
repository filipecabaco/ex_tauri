defmodule Mix.Tasks.ExTauri.Install do
  @moduledoc """
  Installs and configures Tauri in your Phoenix project.

  Uses [Igniter](https://hexdocs.pm/igniter) for safe, AST-aware modifications
  to your Elixir project files, then sets up the Tauri project structure with
  Rust code, capabilities, and a JS bridge.

  ## Usage

      $ mix ex_tauri.install

  ## What It Does

  1. **Sets default config** (via Igniter) — `app_name`, `host`, `port`, `version`
     in `config/config.exs` (only if not already configured)

  2. **Configures Elixir project** (via Igniter):
     - Adds `ExTauri.ShutdownManager` to your supervision tree
     - Adds a `:desktop` release to your `mix.exs`

  3. **Installs Tauri CLI** — Downloads via Cargo

  4. **Initializes Tauri project** — Creates `src-tauri/` structure

  5. **Generates integration code**:
     - Rust main.rs with heartbeat and graceful shutdown
     - Tauri V2 capabilities and permissions
     - LiveView JS hook for Tauri bridge

  6. **Auto-injects hooks**:
     - Imports `TauriHook` in `assets/js/app.js`
     - Registers the hook in the LiveSocket constructor
     - Adds `<div id="tauri-bridge">` to the root layout

  ## Next Steps

  After installation, just run:

      $ mix ex_tauri.dev

  Review the generated config in `config/config.exs` to customize your
  app name, port, or window settings.

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Installs and configures Tauri in your project"

  use Igniter.Mix.Task

  @impl Igniter.Mix.Task
  def info(_argv, _composing_task) do
    %Igniter.Mix.Task.Info{
      group: :ex_tauri,
      example: "mix ex_tauri.install"
    }
  end

  @impl Igniter.Mix.Task
  def igniter(igniter) do
    # Phase 1: Set default config values (only if not already set)
    igniter = configure_defaults(igniter)

    # Phase 2: Set up Tauri project (CLI install, Rust files, JSON, JS, auto-inject hooks)
    ExTauri.Install.Helpers.setup_tauri_project()

    # Phase 3: Modify Elixir project with Igniter (AST-aware, safe)
    igniter
    |> Igniter.Project.Application.add_new_child(ExTauri.ShutdownManager)
    |> add_desktop_release()
    |> Igniter.add_notice("""
    ExTauri installed successfully!

    Next steps:
    1. Review the ExTauri config in config/config.exs (app_name, host, port)

    2. Add Burrito wrapping to your :desktop release for production:

        releases: [desktop: [steps: [:assemble, &Burrito.wrap/1], burrito: [...]]]

    3. Run: mix ex_tauri.dev
    """)
  end

  defp configure_defaults(igniter) do
    # Derive a human-readable app name from the Mix project atom
    app_name =
      Mix.Project.config()[:app]
      |> to_string()
      |> String.split("_")
      |> Enum.map_join(" ", &String.capitalize/1)

    igniter
    |> Igniter.Project.Config.configure_new(
      "config.exs",
      :ex_tauri,
      [:app_name],
      app_name
    )
    |> Igniter.Project.Config.configure_new(
      "config.exs",
      :ex_tauri,
      [:host],
      "localhost"
    )
    # {:code, ...} emits `4000` as an integer literal in the config file,
    # rather than a quoted string "4000"
    |> Igniter.Project.Config.configure_new(
      "config.exs",
      :ex_tauri,
      [:port],
      {:code, Sourceror.parse_string!("4000")}
    )
    |> Igniter.Project.Config.configure_new(
      "config.exs",
      :ex_tauri,
      [:version],
      ExTauri.latest_version()
    )
  end

  defp add_desktop_release(igniter) do
    Igniter.Project.MixProject.update(
      igniter,
      :project,
      [:releases, :desktop, :steps],
      fn
        nil ->
          # Start with a standard release. Users add &Burrito.wrap/1 when ready
          # for production: steps: [:assemble, &Burrito.wrap/1]
          {:ok, {:code, Sourceror.parse_string!("[:assemble]")}}

        zipper ->
          # Already configured, don't overwrite
          {:ok, zipper}
      end
    )
  end
end
