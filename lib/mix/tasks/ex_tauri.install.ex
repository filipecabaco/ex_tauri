defmodule Mix.Tasks.ExTauri.Install do
  @moduledoc """
  Installs Tauri dependency

    $ mix tauri.install
  By default, it installs #{ExTauri.latest_version()} but you
  can configure it in your config files, such as:

      config :ex_tauri, :version, "#{ExTauri.latest_version()}"
  """

  use Mix.Task

  @impl true
  def run(args) do
    ExTauri.install(args)
  end
end
