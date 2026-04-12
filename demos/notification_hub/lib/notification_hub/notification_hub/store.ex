defmodule NotificationHub.Notifications.Store do
  @moduledoc """
  In-memory store for notifications. Holds notifications capped at
  @max_entries, and broadcasts changes via Phoenix.PubSub.
  """

  use GenServer

  alias NotificationHub.Notifications.Notification
  alias Phoenix.PubSub

  @topic "notification_hub"
  @max_entries 500

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  def list, do: GenServer.call(__MODULE__, :list)
  def push(%Notification{} = n), do: GenServer.cast(__MODULE__, {:push, n})
  def mark_read(id), do: GenServer.cast(__MODULE__, {:mark_read, id})
  def mark_all_read(source \\ :all), do: GenServer.cast(__MODULE__, {:mark_all_read, source})
  def dismiss(id), do: GenServer.cast(__MODULE__, {:dismiss, id})

  def snooze(id, minutes) when is_integer(minutes) and minutes > 0 do
    GenServer.cast(__MODULE__, {:snooze, id, minutes})
  end

  def clear, do: GenServer.cast(__MODULE__, :clear)
  def topic, do: @topic
  def subscribe, do: PubSub.subscribe(NotificationHub.PubSub, @topic)

  @impl true
  def init(_opts), do: {:ok, %{notifications: []}}

  @impl true
  def handle_call(:list, _from, state), do: {:reply, state.notifications, state}

  @impl true
  def handle_cast({:push, notification}, state) do
    notifications = [notification | state.notifications] |> Enum.take(@max_entries)
    broadcast({:notification_added, notification})
    {:noreply, %{state | notifications: notifications}}
  end

  def handle_cast({:mark_read, id}, state) do
    notifications = update(state.notifications, id, &%{&1 | read: true})
    broadcast(:notifications_changed)
    {:noreply, %{state | notifications: notifications}}
  end

  def handle_cast({:mark_all_read, source}, state) do
    notifications =
      Enum.map(state.notifications, fn n ->
        if source == :all or n.source == source, do: %{n | read: true}, else: n
      end)

    broadcast(:notifications_changed)
    {:noreply, %{state | notifications: notifications}}
  end

  def handle_cast({:dismiss, id}, state) do
    notifications = update(state.notifications, id, &%{&1 | dismissed: true, read: true})
    broadcast(:notifications_changed)
    {:noreply, %{state | notifications: notifications}}
  end

  def handle_cast({:snooze, id, minutes}, state) do
    until = DateTime.add(DateTime.utc_now(), minutes * 60, :second)
    notifications = update(state.notifications, id, &%{&1 | snoozed_until: until, read: true})
    broadcast(:notifications_changed)
    {:noreply, %{state | notifications: notifications}}
  end

  def handle_cast(:clear, _state) do
    broadcast(:notifications_changed)
    {:noreply, %{notifications: []}}
  end

  defp update(list, id, fun) do
    Enum.map(list, fn
      %Notification{id: ^id} = n -> fun.(n)
      other -> other
    end)
  end

  defp broadcast(msg), do: PubSub.broadcast(NotificationHub.PubSub, @topic, msg)
end
