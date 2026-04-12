defmodule NotificationHub.Notifications.Supervisor do
  @moduledoc """
  Supervises the Store and every registered source.

  Each source runs under the same :one_for_one supervisor so a crash
  in one provider can never take down the others.
  """

  use Supervisor

  alias NotificationHub.Notifications.{Store, Sources}

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      Store,
      Sources.GitHub,
      Sources.Linear,
      Sources.Gmail,
      Sources.Slack
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def sources do
    [Sources.GitHub, Sources.Linear, Sources.Gmail, Sources.Slack]
  end
end
