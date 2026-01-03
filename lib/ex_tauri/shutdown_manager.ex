defmodule ExTauri.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the Phoenix application when running as a Tauri sidecar.

  This GenServer should be added to your application's supervision tree to ensure
  the Phoenix app shuts down gracefully when the Tauri app exits (e.g., via CMD+Q).

  ## Usage

  Add this to your application's supervision tree in `application.ex`:

      def start(_type, _args) do
        children = [
          ExTauri.ShutdownManager,
          # ... your other children
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## How it works

  When running as a Tauri sidecar, the Rust frontend will send SIGTERM to this
  process when the app is exiting. This GenServer traps exits and performs
  graceful shutdown, allowing the application to:
  - Close database connections
  - Flush logs
  - Complete in-flight requests
  - Perform any other cleanup needed

  After cleanup, it initiates a graceful shutdown of the entire application.
  """

  use GenServer
  require Logger

  @shutdown_timeout 5_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Trap exits so we can perform graceful shutdown
    Process.flag(:trap_exit, true)

    # Register this process to handle SIGTERM
    # This allows the Rust side to send SIGTERM for graceful shutdown
    :os.set_signal(:sigterm, :handle)

    Logger.info("[ExTauri.ShutdownManager] Started - ready for graceful shutdown")

    {:ok, %{shutdown_initiated: false}}
  end

  @impl true
  def handle_info({:signal, :sigterm}, state) do
    Logger.info("[ExTauri.ShutdownManager] Received SIGTERM - initiating graceful shutdown")
    initiate_shutdown(state)
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) do
    Logger.info("[ExTauri.ShutdownManager] Received EXIT signal: #{inspect(reason)}")
    initiate_shutdown(state)
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[ExTauri.ShutdownManager] Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("[ExTauri.ShutdownManager] Terminating: #{inspect(reason)}")
    :ok
  end

  defp initiate_shutdown(%{shutdown_initiated: true} = state) do
    # Shutdown already in progress, ignore
    {:noreply, state}
  end

  defp initiate_shutdown(state) do
    Logger.info("[ExTauri.ShutdownManager] Starting graceful shutdown sequence...")

    # Perform any cleanup here if needed
    # For example, you could broadcast a shutdown event to LiveView clients
    # Phoenix.PubSub.broadcast(MyApp.PubSub, "system", {:shutdown, :graceful})

    # Give the system a moment to clean up
    Process.sleep(100)

    # Initiate system shutdown
    Task.start(fn ->
      Logger.info("[ExTauri.ShutdownManager] Stopping application...")
      System.stop(0)
    end)

    {:noreply, %{state | shutdown_initiated: true}}
  end
end
