defmodule PomodoroFarm.Pomodoros do
  @moduledoc """
  Public API for the Pomodoro timer farm.

  Each active timer is its own supervised GenServer. This module
  spawns timers through a DynamicSupervisor, lists the currently
  running ones, and exposes the PubSub topic.
  """

  alias PomodoroFarm.Pomodoros.Timer
  alias Phoenix.PubSub

  @topic "pomodoros"

  def topic, do: @topic
  def subscribe, do: PubSub.subscribe(PomodoroFarm.PubSub, @topic)

  def start_timer(attrs) do
    attrs = Map.put(attrs, :id, random_id())

    case DynamicSupervisor.start_child(__MODULE__.TimerSupervisor, {Timer, attrs}) do
      {:ok, _pid} -> {:ok, Timer.state(attrs.id)}
      {:error, _} = err -> err
    end
  end

  def list do
    DynamicSupervisor.which_children(__MODULE__.TimerSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> safe_fetch(pid) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.started_at, {:asc, DateTime})
  end

  def toggle(id), do: Timer.toggle(id)
  def reset(id), do: Timer.reset(id)
  def stop(id), do: Timer.stop(id)

  def presets do
    [
      %{label: "Deep work", duration_s: 25 * 60},
      %{label: "Short break", duration_s: 5 * 60},
      %{label: "Long break", duration_s: 15 * 60},
      %{label: "Sprint", duration_s: 60}
    ]
  end

  defp safe_fetch(pid) do
    GenServer.call(pid, :state, 500)
  catch
    :exit, _ -> nil
  end

  defp random_id do
    :crypto.strong_rand_bytes(6) |> Base.hex_encode32(padding: false, case: :lower)
  end
end
