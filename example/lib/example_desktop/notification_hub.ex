defmodule ExampleDesktop.NotificationHub do
  @moduledoc """
  Public API for the notification hub demo.

  Thin wrapper over `ExampleDesktop.NotificationHub.Store` plus a few
  helpers to enumerate the available sources. All real work (holding
  state, broadcasting via PubSub, generating demo events) happens in the
  supervised processes under `ExampleDesktop.NotificationHub.Supervisor`.
  """

  alias ExampleDesktop.NotificationHub.{Notification, Store, Supervisor}

  @doc "Returns the notifications visible in the inbox (non-dismissed, non-snoozed)."
  def inbox do
    now = DateTime.utc_now()

    Store.list()
    |> Enum.reject(& &1.dismissed)
    |> Enum.reject(&snoozed?(&1, now))
  end

  @doc "Lists every notification in the store including dismissed ones."
  def list_all, do: Store.list()

  @doc "Adds a notification to the hub (used by non-source emitters like the Pomodoro demo)."
  def push(%Notification{} = notification), do: Store.push(notification)

  defdelegate mark_read(id), to: Store
  def mark_all_read(source \\ :all), do: Store.mark_all_read(source)
  defdelegate dismiss(id), to: Store
  defdelegate snooze(id, minutes), to: Store
  defdelegate clear, to: Store
  defdelegate subscribe, to: Store
  defdelegate topic, to: Store

  @doc "Returns display info for every registered source plus an \"All\" entry."
  def source_filters do
    sources = Enum.map(Supervisor.sources(), & &1.info())
    [%{key: :all, name: "All", color: "indigo", icon: "hero-rectangle-stack"} | sources]
  end

  @doc "Convenience stats used by the UI."
  def stats(notifications) do
    by_source =
      notifications
      |> Enum.group_by(& &1.source)
      |> Map.new(fn {source, list} ->
        {source, %{total: length(list), unread: Enum.count(list, &(not &1.read))}}
      end)

    %{
      total: length(notifications),
      unread: Enum.count(notifications, &(not &1.read)),
      urgent: Enum.count(notifications, &(&1.priority in [:high, :urgent])),
      by_source: by_source
    }
  end

  defp snoozed?(%Notification{snoozed_until: nil}, _now), do: false

  defp snoozed?(%Notification{snoozed_until: until}, now) do
    DateTime.compare(until, now) == :gt
  end
end
