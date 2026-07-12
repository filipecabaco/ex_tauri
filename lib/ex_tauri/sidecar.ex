defmodule ExTauri.Sidecar do
  @moduledoc """
  Behaviour and registry for the sidecar "shim" ExTauri generates at
  `burrito_out/desktop-<triplet>` — the executable Tauri spawns to launch your
  application.

  ExTauri ships two built-in shims:

    * `:phx_server` (alias `:dev_server`, the default) — runs a dev-server
      command directly so hot/live reload works inside the Tauri window. The
      command defaults to `mix phx.server` but is configurable, so you are not
      tied to Phoenix:

          # config/config.exs — run Francis instead of Phoenix
          config :ex_tauri, :dev_command, ~w(mix francis.server)

    * `:release` — builds a standard (non-Burrito) Elixir release and execs it,
      exercising release boot, runtime config, and migrations.

  For anything the `:dev_command` config can't express, implement this
  behaviour and register it under a name of your choosing:

      defmodule MyApp.Sidecar.Custom do
        @behaviour ExTauri.Sidecar

        @impl true
        def script(ctx) do
          \"\"\"
          #!/bin/sh
          cd "\#{ctx.project_root}" || exit 1
          exec mix run --no-halt
          \"\"\"
        end
      end

      # config/config.exs
      config :ex_tauri, :sidecars, %{custom: MyApp.Sidecar.Custom}

  Then select it: `mix ex_tauri.dev --sidecar custom` (or
  `ExTauri.run_dev(["dev"], sidecar: :custom)`).
  """

  @typedoc """
  Context passed to a sidecar's callbacks.

    * `:triplet` — the Rust host target triple (e.g. `"aarch64-apple-darwin"`)
    * `:project_root` — absolute path to the project root
    * `:path` — absolute path the shim must be written to (Tauri's sidecar location)
    * `:port` — the configured dev-server port
  """
  @type context :: %{
          triplet: String.t(),
          project_root: String.t(),
          path: String.t(),
          port: integer()
        }

  @doc """
  Optional build step run before the shim is written (e.g. build a release).
  """
  @callback prepare(context) :: :ok

  @doc """
  Returns the shell script written to `context.path` and made executable.
  """
  @callback script(context) :: iodata()

  @optional_callbacks prepare: 1

  @builtins %{
    phx_server: ExTauri.Sidecar.DevServer,
    dev_server: ExTauri.Sidecar.DevServer,
    release: ExTauri.Sidecar.Release
  }

  @doc """
  Resolves `name`, runs its optional `prepare/1`, then writes and `chmod`s the
  shim at `burrito_out/desktop-<triplet>`.
  """
  @spec generate(atom(), keyword()) :: :ok
  def generate(name, ctx_overrides \\ []) do
    provider = resolve(name)
    ctx = context(ctx_overrides)

    if function_exported?(provider, :prepare, 1), do: provider.prepare(ctx)

    File.mkdir_p!(Path.dirname(ctx.path))
    File.write!(ctx.path, provider.script(ctx))
    File.chmod!(ctx.path, 0o755)
    :ok
  end

  @doc """
  Maps a name to a sidecar module. Built-ins and any modules registered under
  `config :ex_tauri, :sidecars` share one namespace; a module implementing this
  behaviour may also be passed directly.
  """
  @spec resolve(atom()) :: module()
  def resolve(name) when is_atom(name) do
    registry = Map.merge(@builtins, Application.get_env(:ex_tauri, :sidecars, %{}))

    cond do
      module = Map.get(registry, name) -> module
      module = sidecar_module(name) -> module
      true -> raise ArgumentError, unknown_sidecar_message(name)
    end
  end

  # A bare module that implements the behaviour resolves to itself; `false` otherwise.
  defp sidecar_module(name) do
    Code.ensure_loaded?(name) and function_exported?(name, :script, 1) and name
  end

  defp unknown_sidecar_message(name) do
    """
    Unknown sidecar #{inspect(name)}.

    Built-in: #{@builtins |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &inspect/1)}.
    Register custom shims with `config :ex_tauri, :sidecars, %{name: MyModule}`.
    """
  end

  defp context(overrides) do
    triplet = Keyword.get_lazy(overrides, :triplet, &ExTauri.host_triplet/0)

    %{
      triplet: triplet,
      project_root: Keyword.get_lazy(overrides, :project_root, &File.cwd!/0),
      path: Keyword.get(overrides, :path, "burrito_out/desktop-#{triplet}"),
      port: Keyword.get(overrides, :port, Application.get_env(:ex_tauri, :port, 4000))
    }
  end
end
