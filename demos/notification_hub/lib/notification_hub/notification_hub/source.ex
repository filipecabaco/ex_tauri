defmodule NotificationHub.Notifications.Source do
  @moduledoc """
  Behaviour and shared scaffolding for notification sources.

  Each source is a GenServer that periodically generates fake
  notifications and pushes them into the Store. In a real integration
  you'd replace `generate/0` with an API client call.

  Because every source is its own supervised process, one failing
  provider can never take down the others.

  Usage:

      defmodule MySource do
        use NotificationHub.Notifications.Source,
          min_interval: 5_000,
          max_interval: 15_000,
          seed_count: 2

        @impl true
        def info, do: %{key: :my, name: "My", color: "indigo", icon: "hero-sparkles"}

        @impl true
        def generate, do: %Notification{...}
      end
  """

  alias NotificationHub.Notifications.Notification

  @callback info() :: %{key: atom(), name: String.t(), color: String.t(), icon: String.t()}
  @callback generate() :: Notification.t()

  defmacro __using__(opts) do
    min = Keyword.fetch!(opts, :min_interval)
    max = Keyword.fetch!(opts, :max_interval)
    seed = Keyword.get(opts, :seed_count, 2)

    quote do
      use GenServer

      @behaviour NotificationHub.Notifications.Source

      alias NotificationHub.Notifications.Store

      def start_link(opts \\ []) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end

      @impl true
      def init(_opts), do: {:ok, %{}, {:continue, :seed}}

      @impl true
      def handle_continue(:seed, state) do
        for _ <- 1..unquote(seed), do: Store.push(generate())
        schedule_tick()
        {:noreply, state}
      end

      @impl true
      def handle_info(:tick, state) do
        Store.push(generate())
        schedule_tick()
        {:noreply, state}
      end

      defp schedule_tick do
        interval = Enum.random(unquote(min)..unquote(max))
        Process.send_after(self(), :tick, interval)
      end
    end
  end

  def default_actions do
    [
      %{id: "open", label: "Open", style: :primary},
      %{id: "mark_read", label: "Mark read", style: :ghost},
      %{id: "snooze", label: "Snooze 15m", style: :ghost},
      %{id: "dismiss", label: "Dismiss", style: :danger}
    ]
  end
end
