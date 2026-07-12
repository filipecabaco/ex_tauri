defmodule ExTauri.Sidecar.Release do
  @moduledoc """
  Sidecar shim that builds a standard (non-Burrito) Elixir release and execs it.

  Slower than `ExTauri.Sidecar.DevServer` because it builds a release, but it
  exercises release boot, runtime config, and migrations — useful for catching
  problems that only surface in a packaged build without waiting for a full
  Burrito production build.
  """

  @behaviour ExTauri.Sidecar

  @impl true
  def prepare(_ctx) do
    get_in(Mix.Project.config(), [:releases, :desktop]) ||
      raise "expected a :desktop release configured in your mix.exs"

    # Build a standard release without Burrito wrapping for faster dev iteration.
    # Use MIX_ENV=prod to avoid serialization issues with dev config regexes.
    case System.cmd("mix", ["release", "desktop", "--overwrite"],
           env: [{"MIX_ENV", "prod"}, {"BURRITO_SKIP", "true"}],
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, exit_code} -> raise "Failed to build dev release with exit code #{exit_code}."
    end
  end

  @impl true
  def script(%{project_root: root}) do
    # The standard release binary lives at _build/prod/rel/desktop/bin/desktop.
    release_bin = Path.join([root, "_build", "prod", "rel", "desktop", "bin", "desktop"])

    """
    #!/bin/sh
    exec "#{release_bin}" start "$@"
    """
  end
end
