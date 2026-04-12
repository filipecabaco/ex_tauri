defmodule ExampleDesktop.Pomodoros.Timer do
  @moduledoc """
  A single Pomodoro timer, implemented as its own `GenServer`.

  Each running timer lives in its own supervised process — the whole
  point of the demo is that you can spawn dozens of independent timers
  and they all tick in parallel, without ever blocking the LiveView
  socket. When one crashes, the `DynamicSupervisor` restarts only that
  one; the rest keep counting down.

  Timers broadcast state transitions on a shared `Phoenix.PubSub` topic
  so the LiveView can render updates without polling.
  """

  use GenServer, restart: :transient

  alias ExampleDesktop.NotificationHub
  alias ExampleDesktop.NotificationHub.Notification
  alias ExampleDesktop.Pomodoros
  alias Phoenix.PubSub

  @type status :: :running | :paused | :completed

  @type t :: %__MODULE__{
          id: String.t(),
          label: String.t(),
          duration_s: non_neg_integer(),
          remaining_s: non_neg_integer(),
          status: status(),
          started_at: DateTime.t()
        }

  @enforce_keys [:id, :label, :duration_s, :remaining_s, :status, :started_at]
  defstruct [:id, :label, :duration_s, :remaining_s, :status, :started_at]

  # ------------------------------------------------------------------
  # Client API
  # ------------------------------------------------------------------

  def start_link(attrs) do
    GenServer.start_link(__MODULE__, attrs, name: via(attrs.id))
  end

  def child_spec(attrs) do
    %{
      id: {__MODULE__, attrs.id},
      start: {__MODULE__, :start_link, [attrs]},
      restart: :transient
    }
  end

  def state(id), do: GenServer.call(via(id), :state)
  def toggle(id), do: GenServer.cast(via(id), :toggle)
  def reset(id), do: GenServer.cast(via(id), :reset)
  def stop(id), do: GenServer.cast(via(id), :stop)

  defp via(id), do: {:via, Registry, {Pomodoros.Registry, id}}

  # ------------------------------------------------------------------
  # Server callbacks
  # ------------------------------------------------------------------

  @impl true
  def init(attrs) do
    state = %__MODULE__{
      id: attrs.id,
      label: attrs.label,
      duration_s: attrs.duration_s,
      remaining_s: attrs.duration_s,
      status: :running,
      started_at: DateTime.utc_now()
    }

    schedule_tick()
    broadcast({:timer_started, state})
    {:ok, state}
  end

  @impl true
  def handle_call(:state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:toggle, %{status: :running} = state) do
    new_state = %{state | status: :paused}
    broadcast({:timer_updated, new_state})
    {:noreply, new_state}
  end

  def handle_cast(:toggle, %{status: :paused} = state) do
    new_state = %{state | status: :running}
    schedule_tick()
    broadcast({:timer_updated, new_state})
    {:noreply, new_state}
  end

  def handle_cast(:toggle, state), do: {:noreply, state}

  def handle_cast(:reset, state) do
    new_state = %{state | remaining_s: state.duration_s, status: :running}
    schedule_tick()
    broadcast({:timer_updated, new_state})
    {:noreply, new_state}
  end

  def handle_cast(:stop, state) do
    broadcast({:timer_removed, state.id})
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:tick, %{status: :running, remaining_s: r} = state) when r > 1 do
    new_state = %{state | remaining_s: r - 1}
    schedule_tick()
    broadcast({:timer_updated, new_state})
    {:noreply, new_state}
  end

  def handle_info(:tick, %{status: :running} = state) do
    new_state = %{state | remaining_s: 0, status: :completed}
    broadcast({:timer_completed, new_state})
    push_hub_notification(new_state)
    {:noreply, new_state}
  end

  def handle_info(:tick, state), do: {:noreply, state}

  defp schedule_tick, do: Process.send_after(self(), :tick, 1_000)

  defp broadcast(msg), do: PubSub.broadcast(ExampleDesktop.PubSub, Pomodoros.topic(), msg)

  defp push_hub_notification(%__MODULE__{label: label, duration_s: duration}) do
    NotificationHub.push(%Notification{
      id: Notification.new_id(),
      source: :pomodoro,
      kind: "timer_completed",
      title: "Pomodoro complete: #{label}",
      body: "Your #{format_duration(duration)} session just wrapped up — time for a break!",
      actor: "Pomodoro",
      url: nil,
      priority: :high,
      received_at: DateTime.utc_now(),
      actions: [
        %{id: "mark_read", label: "Got it", style: :primary},
        %{id: "dismiss", label: "Dismiss", style: :ghost}
      ]
    })
  end

  defp format_duration(seconds) when seconds >= 60 do
    "#{div(seconds, 60)} min"
  end

  defp format_duration(seconds), do: "#{seconds}s"
end
