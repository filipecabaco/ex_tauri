defmodule ExampleDesktop.Pomodoros.Supervisor do
  @moduledoc """
  Top-level supervisor for the Pomodoro demo.

  Starts a `Registry` used to look timers up by their id and a
  `DynamicSupervisor` that owns every running timer process. The
  `DynamicSupervisor` uses a `:one_for_one` strategy so that crashing
  a single timer never affects its siblings.
  """

  use Supervisor

  alias ExampleDesktop.Pomodoros

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
