defmodule Mix.Tasks.Tauri do
  @shortdoc "Invokes Tauri with the profile and args"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    Tauri.run(args)
  end
end
