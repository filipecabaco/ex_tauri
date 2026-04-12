defmodule ExampleDesktop.Pomodoros do
  @moduledoc """
  Public API for the Pomodoro timer demo.

  Each active timer is its own supervised `GenServer` — see
  `ExampleDesktop.Pomodoros.Timer`. This module is a thin context that
  spawns timers through a `DynamicSupervisor`, lists the currently
  running ones, and exposes the PubSub topic used to broadcast state
  changes.
  """

  alias ExampleDesktop.Pomodoros.Timer
  alias Phoenix.PubSub

  @topic "pomodoros"

  @doc "Returns the PubSub topic used by the Pomodoro demo."
  def topic, do: @topic

  @doc "Subscribes the caller to Pomodoro events."
  def subscribe, do: PubSub.subscribe(ExampleDesktop.PubSub, @topic)

  @doc """
  Starts a new timer under the dynamic supervisor.

  Expects a map with `:label` (string) and `:duration_s` (integer in
  seconds). Returns the full timer state on success.
  """
  def start_timer(attrs) do
    attrs = Map.put(attrs, :id, random_id())

    case DynamicSupervisor.start_child(__MODULE__.TimerSupervisor, {Timer, attrs}) do
      {:ok, _pid} -> {:ok, Timer.state(attrs.id)}
      {:error, _} = err -> err
    end
  end

  @doc "Lists every currently-running timer, sorted by start time."
  def list do
    DynamicSupervisor.which_children(__MODULE__.TimerSupervisor)
    |> Enum.map(fn {_, pid, _, _} -> safe_fetch(pid) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.started_at, {:asc, DateTime})
  end

  @doc "Toggles a timer between running and paused."
  def toggle(id), do: Timer.toggle(id)

  @doc "Resets a timer back to its full duration."
  def reset(id), do: Timer.reset(id)

  @doc "Stops and removes a timer."
  def stop(id), do: Timer.stop(id)

  @doc "Presets the UI exposes as quick-start buttons."
  def presets do
    [
      %{label: "Deep work", duration_s: 25 * 60, emoji: "focus"},
      %{label: "Short break", duration_s: 5 * 60, emoji: "break"},
      %{label: "Long break", duration_s: 15 * 60, emoji: "coffee"},
      %{label: "Sprint", duration_s: 60, emoji: "bolt"}
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
