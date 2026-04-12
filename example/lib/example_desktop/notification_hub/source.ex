defmodule ExampleDesktop.NotificationHub.Source do
  @moduledoc """
  Behaviour and shared scaffolding for notification sources.

  A source is a `GenServer` responsible for producing notifications
  (typically by polling or streaming from a third-party API) and pushing
  them into `ExampleDesktop.NotificationHub.Store`. The store then
  broadcasts to any subscribed LiveViews.

  For the demo, each concrete source generates fake notifications on a
  random interval. In a real integration you would replace `generate/0`
  with an API client call. Because every source is its own supervised
  process, one failing provider can never take down the others — that is
  precisely the kind of fault isolation the BEAM is built for.

  Implementations typically use the `__using__/1` macro below to avoid
  repeating the tick/broadcast boilerplate:

      defmodule MySource do
        use ExampleDesktop.NotificationHub.Source,
          min_interval: 5_000,
          max_interval: 15_000,
          seed_count: 2

        @impl true
        def info, do: %{key: :my, name: "My", color: "indigo", icon: "hero-sparkles"}

        @impl true
        def generate, do: %Notification{...}
      end
  """

  alias ExampleDesktop.NotificationHub.Notification

  @doc "Returns display metadata about the source (name, icon, colour)."
  @callback info() :: %{key: atom(), name: String.t(), color: String.t(), icon: String.t()}

  @doc "Produces a single notification (usually a random one, for the demo)."
  @callback generate() :: Notification.t()

  defmacro __using__(opts) do
    min = Keyword.fetch!(opts, :min_interval)
    max = Keyword.fetch!(opts, :max_interval)
    seed = Keyword.get(opts, :seed_count, 2)

    quote do
      use GenServer

      @behaviour ExampleDesktop.NotificationHub.Source

      alias ExampleDesktop.NotificationHub.Store

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

  @doc "Default actions offered for every notification kind."
  def default_actions do
    [
      %{id: "open", label: "Open", style: :primary},
      %{id: "mark_read", label: "Mark read", style: :ghost},
      %{id: "snooze", label: "Snooze 15m", style: :ghost},
      %{id: "dismiss", label: "Dismiss", style: :danger}
    ]
  end
end
