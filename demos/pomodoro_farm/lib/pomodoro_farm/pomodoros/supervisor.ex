defmodule PomodoroFarm.Pomodoros.Supervisor do
  @moduledoc """
  Top-level supervisor for the Pomodoro demo.

  Starts a Registry (unique keys, for id -> pid lookup) and a
  DynamicSupervisor that owns every running timer process.
  """

  use Supervisor

  alias PomodoroFarm.Pomodoros

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Pomodoros.Registry},
      {DynamicSupervisor, name: Pomodoros.TimerSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
