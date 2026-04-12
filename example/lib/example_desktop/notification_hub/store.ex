defmodule ExampleDesktop.NotificationHub.Store do
  @moduledoc """
  In-memory store for notifications aggregated by the hub.

  The store is a `GenServer` that holds every notification the hub has
  seen (capped at `@max_entries`). Any write broadcasts a message on
  `Phoenix.PubSub` so that LiveViews can refresh without polling.

  Real integrations would back this with ETS, SQLite or a remote store,
  but for the demo we keep everything in process state — the BEAM happily
  handles thousands of small maps.
  """

  use GenServer

  alias ExampleDesktop.NotificationHub.Notification
  alias Phoenix.PubSub

  @topic "notification_hub"
  @max_entries 500

  # ------------------------------------------------------------------
  # Client API
  # ------------------------------------------------------------------

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Lists all notifications, most-recent first."
  def list, do: GenServer.call(__MODULE__, :list)

  @doc "Adds a notification and broadcasts a `{:notification_added, n}` event."
  def push(%Notification{} = notification) do
    GenServer.cast(__MODULE__, {:push, notification})
  end

  def mark_read(id), do: GenServer.cast(__MODULE__, {:mark_read, id})

  @doc "Marks every non-dismissed notification as read (optionally scoped to a source)."
  def mark_all_read(source \\ :all), do: GenServer.cast(__MODULE__, {:mark_all_read, source})

  def dismiss(id), do: GenServer.cast(__MODULE__, {:dismiss, id})

  def snooze(id, minutes) when is_integer(minutes) and minutes > 0 do
    GenServer.cast(__MODULE__, {:snooze, id, minutes})
  end

  @doc "Drops every notification from the store."
  def clear, do: GenServer.cast(__MODULE__, :clear)

  @doc "Returns the PubSub topic used for store broadcasts."
  def topic, do: @topic

  @doc "Subscribes the caller to store events."
  def subscribe, do: PubSub.subscribe(ExampleDesktop.PubSub, @topic)

  # ------------------------------------------------------------------
  # Server callbacks
  # ------------------------------------------------------------------

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
        if source == :all or n.source == source do
          %{n | read: true}
        else
          n
        end
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

  defp broadcast(msg), do: PubSub.broadcast(ExampleDesktop.PubSub, @topic, msg)
end
