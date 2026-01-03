defmodule ExTauri.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the Phoenix application when running as a Tauri sidecar.

  This GenServer implements a heartbeat-based mechanism to detect when the Tauri
  frontend exits. The Rust frontend sends heartbeat signals every 100ms via Unix
  domain socket, and if the Phoenix sidecar doesn't receive a heartbeat within 300ms,
  it initiates graceful shutdown.

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

  The heartbeat mechanism provides robust shutdown detection:
  1. ShutdownManager creates a Unix domain socket at `/tmp/tauri_heartbeat.sock`
  2. Rust frontend connects and sends a byte every 100ms
  3. ShutdownManager tracks the last heartbeat timestamp
  4. Every 100ms, ShutdownManager checks if a heartbeat was received recently
  5. If no heartbeat for 300ms (3 missed beats), initiates graceful shutdown

  This works even if:
  - The Tauri app is force-quit (CMD+Q)
  - The Tauri app crashes
  - The process is killed unexpectedly

  After detecting heartbeat failure, the Phoenix app:
  - Closes database connections
  - Flushes logs
  - Completes in-flight requests
  - Performs any other cleanup needed
  - Exits gracefully
  """

  use GenServer
  require Logger

  @heartbeat_interval 100
  @heartbeat_timeout 300
  @socket_path "/tmp/tauri_heartbeat.sock"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Trap exits so we can perform graceful shutdown
    Process.flag(:trap_exit, true)

    # Clean up old socket file if it exists
    File.rm(@socket_path)

    # Start Unix domain socket server
    {:ok, listen_socket} = :gen_tcp.listen(0, [
      :binary,
      {:ifaddr, {:local, @socket_path}},
      {:active, false},
      {:reuseaddr, true}
    ])

    # Spawn acceptor process
    spawn_link(fn -> accept_loop(listen_socket) end)

    # Schedule the first heartbeat check
    schedule_heartbeat_check()

    Logger.info("[ExTauri.ShutdownManager] Started - heartbeat monitoring active on #{@socket_path}")

    {:ok,
     %{
       listen_socket: listen_socket,
       last_heartbeat: System.monotonic_time(:millisecond),
       shutdown_initiated: false
     }}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    # Update the last heartbeat timestamp
    {:noreply, %{state | last_heartbeat: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_info(:check_heartbeat, state) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last_heartbeat = current_time - state.last_heartbeat

    if time_since_last_heartbeat > @heartbeat_timeout do
      Logger.warning(
        "[ExTauri.ShutdownManager] Heartbeat timeout (#{time_since_last_heartbeat}ms) - Tauri frontend appears to have exited"
      )

      initiate_shutdown(state)
    else
      # Still receiving heartbeats, schedule next check
      schedule_heartbeat_check()
      {:noreply, state}
    end
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
  def terminate(reason, state) do
    Logger.info("[ExTauri.ShutdownManager] Terminating: #{inspect(reason)}")
    :gen_tcp.close(state.listen_socket)
    File.rm(@socket_path)
    :ok
  end

  defp schedule_heartbeat_check do
    Process.send_after(self(), :check_heartbeat, @heartbeat_interval)
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        # Spawn a process to handle this client
        spawn(fn -> handle_client(client_socket) end)
        # Continue accepting more connections
        accept_loop(listen_socket)

      {:error, reason} ->
        Logger.error("[ExTauri.ShutdownManager] Accept error: #{inspect(reason)}")
    end
  end

  defp handle_client(client_socket) do
    case :gen_tcp.recv(client_socket, 0) do
      {:ok, _data} ->
        # Received heartbeat, notify the GenServer
        GenServer.cast(__MODULE__, :heartbeat)
        # Continue receiving
        handle_client(client_socket)

      {:error, :closed} ->
        :gen_tcp.close(client_socket)

      {:error, reason} ->
        Logger.debug("[ExTauri.ShutdownManager] Client error: #{inspect(reason)}")
        :gen_tcp.close(client_socket)
    end
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
