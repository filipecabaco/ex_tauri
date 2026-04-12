defmodule ExampleDesktop.NotificationHub.Supervisor do
  @moduledoc """
  Supervises the notification hub store and every registered source.

  Each source runs under the same `:one_for_one` supervisor so a crash
  in one provider (e.g. a flaky API client) can never take down the
  others — the BEAM will simply restart the failing process and the
  rest of the hub keeps streaming events.
  """

  use Supervisor

  alias ExampleDesktop.NotificationHub.Store
  alias ExampleDesktop.NotificationHub.Sources

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

  @doc "Returns the list of source modules managed by the supervisor."
  def sources do
    [Sources.GitHub, Sources.Linear, Sources.Gmail, Sources.Slack]
  end
end
