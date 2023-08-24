defmodule Mix.Tasks.Tauri.Install do
  @moduledoc """
  Installs Tauri dependency

    $ mix tauri.install
  By default, it installs #{Tauri.latest_version()} but you
  can configure it in your config files, such as:

      config :tauri, :version, "#{Tauri.latest_version()}"
  """

  use Mix.Task

  @impl true
  def run(args) do
    Tauri.install(args)
  end
end
