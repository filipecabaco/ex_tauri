defmodule NotificationHub.Notifications do
  @moduledoc """
  Public API for the notification hub.

  Thin wrapper over the Store plus helpers to enumerate
  available sources and compute stats.
  """

  alias NotificationHub.Notifications.{Notification, Store, Supervisor}

  def inbox do
    now = DateTime.utc_now()

    Store.list()
    |> Enum.reject(& &1.dismissed)
    |> Enum.reject(&snoozed?(&1, now))
  end

  def list_all, do: Store.list()

  defdelegate mark_read(id), to: Store
  def mark_all_read(source \\ :all), do: Store.mark_all_read(source)
  defdelegate dismiss(id), to: Store
  defdelegate snooze(id, minutes), to: Store
  defdelegate clear, to: Store
  defdelegate subscribe, to: Store
  defdelegate topic, to: Store

  def source_filters do
    sources = Enum.map(Supervisor.sources(), & &1.info())
    [%{key: :all, name: "All", color: "indigo", icon: "hero-rectangle-stack"} | sources]
  end

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
