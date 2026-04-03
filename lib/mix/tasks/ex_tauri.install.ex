if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.ExTauri.Install do
    @moduledoc """
    Installs and configures Tauri in your Phoenix project.

    This task uses [Igniter](https://hexdocs.pm/igniter) for safe, AST-aware
    modifications to your Elixir project files, then sets up the Tauri project
    structure with Rust code, capabilities, and a JS bridge.

    ## Usage

        $ mix ex_tauri.install

    ## What It Does

    1. **Configures Elixir project** (via Igniter):
       - Adds `ExTauri.ShutdownManager` to your supervision tree
       - Adds a `:desktop` Burrito release to your `mix.exs`

    2. **Installs Tauri CLI** - Downloads via Cargo

    3. **Initializes Tauri project** - Creates `src-tauri/` structure

    4. **Generates integration code**:
       - Rust main.rs with heartbeat and graceful shutdown
       - Tauri V2 capabilities and permissions
       - LiveView JS hook for Tauri bridge

    ## Configuration

    Configure Tauri in your `config/config.exs`:

    ```elixir
    config :ex_tauri,
      version: "#{ExTauri.latest_version()}",
      app_name: "My Desktop App",
      host: "localhost",
      port: 4000
    ```

    ## Next Steps

    After installation:

    1. Add the hook to your LiveView JS (assets/js/app.js):

        import { TauriHook } from "../vendor/ex_tauri"

        let liveSocket = new LiveSocket("/live", Socket, {
          hooks: { TauriHook },
        })

    2. Add the hook element to your layout:

        <div id="tauri-bridge" phx-hook="TauriHook"></div>

    3. Run `mix ex_tauri.dev` to start development

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
      # Phase 1: Set up Tauri project (CLI install, Rust files, JSON, JS)
      ExTauri.Install.Helpers.setup_tauri_project()

      # Phase 2: Modify Elixir project with Igniter (AST-aware, safe)
      igniter
      |> Igniter.Project.Application.add_new_child(ExTauri.ShutdownManager)
      |> add_desktop_release()
      |> Igniter.add_notice("""
      ExTauri installed successfully!

      Next steps:
      1. Add the hook to your LiveView JS (assets/js/app.js):

          import { TauriHook } from "../vendor/ex_tauri"

          let liveSocket = new LiveSocket("/live", Socket, {
            hooks: { TauriHook },
          })

      2. Add the hook element to your layout:

          <div id="tauri-bridge" phx-hook="TauriHook"></div>

      3. Run: mix ex_tauri.dev
      """)
    end

    defp add_desktop_release(igniter) do
      Igniter.Project.MixProject.update(
        igniter,
        :project,
        [:releases, :desktop, :steps],
        fn
          nil ->
            {:ok, {:code, Sourceror.parse_string!("[:assemble, &Burrito.wrap/1]")}}

          zipper ->
            # Already configured, don't overwrite
            {:ok, zipper}
        end
      )
    end
  end
else
  defmodule Mix.Tasks.ExTauri.Install do
    @moduledoc """
    Installs and configures Tauri in your Phoenix project.

    For the best experience, add `{:igniter, "~> 0.7"}` to your dependencies.
    Igniter enables automatic, safe modifications to your supervision tree and
    mix.exs configuration. Without it, you'll need to make those changes manually.

    ## Usage

        $ mix ex_tauri.install

    For more information, see: https://github.com/filipecabaco/ex_tauri
    """

    @shortdoc "Installs and configures Tauri in your project"
    @compile {:no_warn_undefined, Mix}

    use Mix.Task

    @impl true
    def run(_args) do
      ExTauri.Install.Helpers.setup_tauri_project()

      Mix.shell().info("""

      ExTauri installed successfully!

      Next steps:
      1. Add the hook to your LiveView JS (assets/js/app.js):

          import { TauriHook } from "../vendor/ex_tauri"

          let liveSocket = new LiveSocket("/live", Socket, {
            hooks: { TauriHook },
          })

      2. Add the hook element to your layout:

          <div id="tauri-bridge" phx-hook="TauriHook"></div>

      3. Add ExTauri.ShutdownManager to your supervision tree
      4. Configure a Burrito release in mix.exs
      5. Run: mix ex_tauri.dev

      Tip: Add {:igniter, "~> 0.7"} to your deps and re-run this task
      to have steps 3-4 done automatically.
      """)
    end
  end
end
