defmodule NotificationHub.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      {Phoenix.PubSub, name: NotificationHub.PubSub},
      NotificationHub.Notifications.Supervisor,
      NotificationHubWeb.Endpoint,
      ExTauri.ShutdownManager
    ]

    opts = [strategy: :one_for_one, name: NotificationHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NotificationHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
