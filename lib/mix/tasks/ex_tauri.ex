defmodule Mix.Tasks.ExTauri do
  @shortdoc "Invokes Tauri with the profile and args"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    ExTauri.run(args)
  end
end
