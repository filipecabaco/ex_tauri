defmodule PomodoroFarm.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: PomodoroFarm.PubSub},
      PomodoroFarm.Pomodoros.Supervisor,
      PomodoroFarmWeb.Endpoint,
      ExTauri.ShutdownManager
    ]

    opts = [strategy: :one_for_one, name: PomodoroFarm.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    PomodoroFarmWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
