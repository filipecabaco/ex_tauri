defmodule ExTauri.ShutdownManager do
  @moduledoc """
  Manages graceful shutdown of the Phoenix application when running as a Tauri sidecar.

  This GenServer implements a heartbeat-based mechanism to detect when the Tauri
  frontend exits. The Rust frontend sends heartbeat signals every 100ms — over a
  Unix domain socket on macOS/Linux, or a localhost TCP socket on Windows — and
  if the Phoenix sidecar doesn't receive a heartbeat within 1500ms (configurable),
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
  1. ShutdownManager opens a listener. On macOS/Linux this is a Unix domain
     socket at `<tmpdir>/tauri_heartbeat_<app_name>.sock`. On Windows (where the
     BEAM cannot listen on Unix domain sockets) it is a TCP socket bound to
     `127.0.0.1` on an ephemeral port, and the port number is written to
     `<tmpdir>/tauri_heartbeat_<app_name>.port` so the Rust frontend can find it
  2. Rust frontend connects and sends a byte every 100ms
  3. The acceptor reads bytes in the same process that accepted the connection and
     casts each one back as a heartbeat (reading from another process would fail)
  4. Every 500ms, ShutdownManager checks if a heartbeat was received recently
  5. Once the frontend has connected at least once, no heartbeat for 1500ms
     initiates graceful shutdown; before the first connection the timeout is not
     enforced, so a slow boot can't shut the app down before the window attaches

  The socket path is unique per application (based on `:app_name` config) to prevent
  collisions when multiple ExTauri applications run simultaneously.

  This works even when:
  - The app is force-quit (CMD+Q on macOS)
  - The app crashes unexpectedly
  - The process is killed without cleanup

  ## Configuration

  Heartbeat timing can be configured in your `config/config.exs`:

      config :ex_tauri,
        heartbeat_interval: 500,  # How often to check heartbeat (ms, default: 500)
        heartbeat_timeout: 1500   # Time without heartbeat before shutdown (ms, default: 1500)

  The transport is selected automatically from the OS (`:unix` on macOS/Linux,
  `:tcp` on Windows). It can be forced with the `:heartbeat_transport` config
  key or the `:transport` start option, which is mainly useful for tests.

  ## The desktop channel

  Beyond liveness, the socket carries a newline-delimited JSON protocol in both
  directions: the Rust frontend sends heartbeats and native events (menu and
  tray clicks), and Elixir sends desktop commands (notifications, tray setup).
  Use `ExTauri.Desktop` rather than talking to this server directly.
  """

  use GenServer
  require Logger

  @default_heartbeat_interval 500
  @default_heartbeat_timeout 1500

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Trap exits so we can perform graceful shutdown
    Process.flag(:trap_exit, true)

    # Options take precedence over application config, which falls back to the
    # built-in defaults. Passing opts (used in tests) keeps configuration
    # explicit and avoids mutating global application env.
    heartbeat_interval =
      opts[:heartbeat_interval] ||
        Application.get_env(:ex_tauri, :heartbeat_interval, @default_heartbeat_interval)

    heartbeat_timeout =
      opts[:heartbeat_timeout] ||
        Application.get_env(:ex_tauri, :heartbeat_timeout, @default_heartbeat_timeout)

    # The action taken once the heartbeat is lost. Defaults to stopping the BEAM;
    # tests inject a benign function so the suite isn't torn down by System.stop/1.
    shutdown_fun = opts[:shutdown_fun] || (&default_shutdown/0)

    # Create socket path using app name to prevent collisions
    app_name = opts[:app_name] || Application.get_env(:ex_tauri, :app_name, "ex_tauri_app")
    socket_name = ExTauri.Paths.sanitize_name(app_name)

    # Unix domain sockets on macOS/Linux; localhost TCP + a port discovery file
    # on Windows, where the BEAM cannot listen on Unix domain sockets.
    transport =
      opts[:transport] ||
        Application.get_env(:ex_tauri, :heartbeat_transport, default_transport())

    {listen_socket, endpoint, cleanup_paths} = open_listener(transport, socket_name)

    # Spawn acceptor process under the ExTauri TaskSupervisor
    Task.Supervisor.start_child(ExTauri.TaskSupervisor, fn -> accept_loop(listen_socket) end)

    # Schedule the first heartbeat check
    schedule_heartbeat_check(heartbeat_interval)

    Logger.info(
      "[ExTauri.ShutdownManager] Started - heartbeat monitoring active on #{endpoint}"
    )

    {:ok,
     %{
       listen_socket: listen_socket,
       cleanup_paths: cleanup_paths,
       last_heartbeat: System.monotonic_time(:millisecond),
       # Stays false until the frontend connects at least once. While false a
       # heartbeat timeout means "still booting", not "window gone".
       connected: false,
       shutdown_initiated: false,
       heartbeat_interval: heartbeat_interval,
       heartbeat_timeout: heartbeat_timeout,
       shutdown_fun: shutdown_fun,
       # Duplex channel state: the currently connected frontend socket (for
       # outbound ExTauri.Desktop commands) and processes subscribed to
       # native events (pid => monitor ref).
       client_socket: nil,
       subscribers: %{}
     }}
  end

  @impl true
  def handle_cast(:heartbeat, state) do
    # Record the heartbeat and mark the frontend as having connected at least once.
    {:noreply, %{state | last_heartbeat: System.monotonic_time(:millisecond), connected: true}}
  end

  def handle_cast({:client_connected, socket}, state) do
    {:noreply, %{state | client_socket: socket}}
  end

  def handle_cast({:client_disconnected, socket}, state) do
    if state.client_socket == socket do
      {:noreply, %{state | client_socket: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:channel_event, name, payload}, state) do
    for {pid, _ref} <- state.subscribers do
      send(pid, {:ex_tauri_event, name, payload})
    end

    {:noreply, state}
  end

  @impl true
  def handle_call({:desktop_command, name, payload}, _from, state) do
    case state.client_socket do
      nil ->
        {:reply, {:error, :not_connected}, state}

      socket ->
        line = Jason.encode!(%{type: "command", name: name, payload: payload}) <> "\n"

        case :gen_tcp.send(socket, line) do
          :ok -> {:reply, :ok, state}
          {:error, reason} -> {:reply, {:error, reason}, %{state | client_socket: nil}}
        end
    end
  end

  def handle_call({:subscribe, pid}, _from, state) do
    if Map.has_key?(state.subscribers, pid) do
      {:reply, :ok, state}
    else
      ref = Process.monitor(pid)
      {:reply, :ok, %{state | subscribers: Map.put(state.subscribers, pid, ref)}}
    end
  end

  def handle_call({:unsubscribe, pid}, _from, state) do
    case Map.pop(state.subscribers, pid) do
      {nil, _subscribers} ->
        {:reply, :ok, state}

      {ref, subscribers} ->
        Process.demonitor(ref, [:flush])
        {:reply, :ok, %{state | subscribers: subscribers}}
    end
  end

  @impl true
  def handle_info(:check_heartbeat, %{connected: false} = state) do
    # Startup grace: the timeout only applies once the frontend has connected at
    # least once. The frontend connects only after the server port is up, so
    # before the first heartbeat "no heartbeat yet" is the still-booting case, not
    # a lost window. Enforcing the timeout here would shut the app down mid-boot.
    schedule_heartbeat_check(state.heartbeat_interval)
    {:noreply, state}
  end

  def handle_info(:check_heartbeat, state) do
    current_time = System.monotonic_time(:millisecond)
    time_since_last_heartbeat = current_time - state.last_heartbeat

    if time_since_last_heartbeat > state.heartbeat_timeout do
      Logger.warning(
        "[ExTauri.ShutdownManager] Heartbeat timeout (#{time_since_last_heartbeat}ms) - Tauri frontend appears to have exited"
      )

      initiate_shutdown(state)
    else
      # Still receiving heartbeats, schedule next check
      schedule_heartbeat_check(state.heartbeat_interval)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:execute_shutdown, state) do
    Logger.info("[ExTauri.ShutdownManager] Stopping application...")
    state.shutdown_fun.()
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:noreply, %{state | subscribers: Map.delete(state.subscribers, pid)}}
  end

  def handle_info(msg, state) do
    Logger.debug("[ExTauri.ShutdownManager] Received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("[ExTauri.ShutdownManager] Terminating: #{inspect(reason)}")
    :gen_tcp.close(state.listen_socket)
    Enum.each(state.cleanup_paths, &File.rm/1)
    :ok
  end

  defp default_shutdown do
    System.stop(0)
  end

  defp default_transport do
    case :os.type() do
      {:win32, _} -> :tcp
      _ -> :unix
    end
  end

  defp open_listener(:unix, socket_name) do
    socket_path = Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.sock")

    # Clean up old socket file if it exists
    File.rm(socket_path)

    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ifaddr, {:local, socket_path}},
        {:active, false},
        {:reuseaddr, true}
      ])

    # Restrict socket to owner-only access (prevents local privilege escalation)
    File.chmod(socket_path, 0o600)

    {listen_socket, socket_path, [socket_path]}
  end

  defp open_listener(:tcp, socket_name) do
    port_file = Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.port")

    # Clean up a stale port file so the frontend can't connect to a dead port
    File.rm(port_file)

    # Bind to loopback only; port 0 lets the OS pick a free ephemeral port,
    # which is then published through the port file for the Rust frontend.
    {:ok, listen_socket} =
      :gen_tcp.listen(0, [
        :binary,
        {:ip, {127, 0, 0, 1}},
        {:active, false},
        {:reuseaddr, true}
      ])

    {:ok, port} = :inet.port(listen_socket)
    File.write!(port_file, Integer.to_string(port))
    File.chmod(port_file, 0o600)

    {listen_socket, "127.0.0.1:#{port}", [port_file]}
  end

  defp schedule_heartbeat_check(interval) do
    Process.send_after(self(), :check_heartbeat, interval)
  end

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket, 1000) do
      {:ok, client_socket} ->
        # Read in THIS process — the one that accepted. recv on a passive socket
        # from a separately-spawned process returns {:error, :closed}, so reading
        # the heartbeat elsewhere silently drops every byte and the frontend never
        # registers as connected. The frontend holds one connection at a time
        # (reconnecting on drop), so handling them sequentially is enough.
        #
        # The manager keeps the socket for outbound ExTauri.Desktop commands
        # (gen_tcp.send is allowed from other processes; only recv is
        # restricted to this one).
        GenServer.cast(__MODULE__, {:client_connected, client_socket})
        recv_loop(client_socket)
        GenServer.cast(__MODULE__, {:client_disconnected, client_socket})
        accept_loop(listen_socket)

      {:error, :timeout} ->
        # Normal timeout, just continue
        accept_loop(listen_socket)

      {:error, :closed} ->
        Logger.info("[ExTauri.ShutdownManager] Listen socket closed, stopping accept loop")

      {:error, reason} ->
        Logger.error("[ExTauri.ShutdownManager] Accept error: #{inspect(reason)}")
    end
  end

  defp recv_loop(client_socket, buffer \\ "") do
    case :gen_tcp.recv(client_socket, 0) do
      {:ok, data} ->
        # Any traffic counts as liveness, whatever its content.
        GenServer.cast(__MODULE__, :heartbeat)
        buffer = process_channel_data(buffer <> data)
        recv_loop(client_socket, buffer)

      {:error, reason} ->
        unless reason == :closed do
          Logger.debug("[ExTauri.ShutdownManager] Client recv error: #{inspect(reason)}")
        end

        :gen_tcp.close(client_socket)
    end
  end

  # The channel protocol is newline-delimited JSON. Complete lines are
  # dispatched; the trailing partial line is returned as the new buffer.
  defp process_channel_data(buffer) do
    case String.split(buffer, "\n") do
      [incomplete] ->
        # Legacy frontends send bare heartbeat bytes with no newlines — don't
        # let them accumulate. Anything protocol-shaped is far smaller.
        if byte_size(incomplete) > 4096, do: "", else: incomplete

      parts ->
        {lines, [rest]} = Enum.split(parts, -1)
        Enum.each(lines, &dispatch_channel_line/1)
        rest
    end
  end

  defp dispatch_channel_line(line) do
    case Jason.decode(line) do
      {:ok, %{"type" => "heartbeat"}} ->
        :ok

      {:ok, %{"type" => "event", "name" => name} = message} ->
        GenServer.cast(__MODULE__, {:channel_event, name, message["payload"]})

      _other ->
        # Unknown or legacy content — already counted as a heartbeat.
        :ok
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

    # Schedule shutdown to give the system a moment to clean up
    # Without blocking the GenServer
    Process.send_after(self(), :execute_shutdown, 100)

    {:noreply, %{state | shutdown_initiated: true}}
  end
end
