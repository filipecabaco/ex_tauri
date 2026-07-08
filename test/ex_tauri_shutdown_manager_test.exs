defmodule ExTauri.ShutdownManagerTest do
  use ExUnit.Case, async: false

  alias ExTauri.ShutdownManager

  # Fast timing keeps the suite snappy. Production defaults (500/1500) are
  # exercised through config, not these per-test timings.
  @interval 50
  @timeout 150

  setup do
    # A unique app name per test keeps each manager on its own socket.
    app_name = "test_app_#{System.unique_integer([:positive])}"
    socket_path = socket_path_for(app_name)

    # start_supervised stops the manager after each test, and terminate/2 removes
    # the socket. This is just a belt-and-suspenders cleanup for stray files.
    on_exit(fn -> File.rm(socket_path) end)

    %{app_name: app_name, socket_path: socket_path}
  end

  # Starts the manager under ExUnit's supervisor. Its parent is then the test
  # supervisor, not the ephemeral test process — so the gen_server parent-exit
  # rule no longer terminates it with :shutdown the instant a test ends, and we
  # don't need a manual GenServer.stop in on_exit.
  #
  # The injected shutdown_fun replaces System.stop/1, so a lost heartbeat sends
  # us a message instead of tearing down the test VM. :restart is :temporary so
  # tests that stop the manager mid-run aren't fighting an automatic restart.
  defp start_manager(ctx, opts \\ []) do
    test_pid = self()

    opts =
      Keyword.merge(
        [
          app_name: ctx.app_name,
          heartbeat_interval: @interval,
          heartbeat_timeout: @timeout,
          shutdown_fun: fn -> send(test_pid, :shutdown_triggered) end
        ],
        opts
      )

    start_supervised!({ShutdownManager, opts}, restart: :temporary)
  end

  describe "start_link/1" do
    test "starts the GenServer and creates the socket file", ctx do
      pid = start_manager(ctx)

      assert Process.alive?(pid)
      assert Process.whereis(ShutdownManager) == pid
      assert wait_for_file(ctx.socket_path)
    end

    test "cleans up a stale socket file on startup", ctx do
      File.write!(ctx.socket_path, "stale")
      assert File.exists?(ctx.socket_path)

      pid = start_manager(ctx)

      assert Process.alive?(pid)
      assert wait_for_file(ctx.socket_path)
    end
  end

  describe "heartbeat mechanism" do
    test "accepts heartbeat connections via the Unix socket", ctx do
      start_manager(ctx)
      assert wait_for_file(ctx.socket_path)

      client = connect(ctx.socket_path)
      assert :ok = :gen_tcp.send(client, "h")
      :gen_tcp.close(client)
    end

    test "a socket heartbeat marks the frontend as connected", ctx do
      pid = start_manager(ctx)
      assert wait_for_file(ctx.socket_path)

      client = connect(ctx.socket_path)
      :ok = :gen_tcp.send(client, "h")

      # The acceptor casts :heartbeat asynchronously; poll until the state reflects it.
      assert eventually(fn -> :sys.get_state(pid).connected end)

      :gen_tcp.close(client)
    end

    test "a direct :heartbeat cast marks the frontend as connected", ctx do
      pid = start_manager(ctx)

      GenServer.cast(ShutdownManager, :heartbeat)

      assert eventually(fn -> :sys.get_state(pid).connected end)
    end

    test "continuous heartbeats keep the manager alive past the timeout", ctx do
      # Generous margins: CI runners (macOS especially) can oversleep by tens
      # of milliseconds, so heartbeat at 1/4 of an enlarged timeout window
      # instead of racing the standard one.
      timeout = @timeout * 4
      start_manager(ctx, heartbeat_timeout: timeout)
      assert wait_for_file(ctx.socket_path)

      client = connect(ctx.socket_path)

      # Heartbeat faster than the timeout across several timeout windows.
      for _ <- 1..6 do
        :gen_tcp.send(client, "h")
        Process.sleep(div(timeout, 4))
      end

      refute_received :shutdown_triggered
      :gen_tcp.close(client)
    end
  end

  describe "shutdown detection" do
    test "does not shut down before the first heartbeat (startup grace)", ctx do
      pid = start_manager(ctx)

      # No heartbeat has ever arrived. Well past the timeout, the manager must NOT
      # shut down — "no heartbeat yet" is the still-booting case, not a lost window.
      refute_receive :shutdown_triggered, @timeout * 5
      refute :sys.get_state(pid).shutdown_initiated
    end

    test "shuts down once the heartbeat is lost", ctx do
      pid = start_manager(ctx)

      # Mark the frontend as having connected once, then stop sending heartbeats.
      # Only now is the timeout enforced.
      GenServer.cast(ShutdownManager, :heartbeat)

      assert_receive :shutdown_triggered, @timeout * 10
      assert :sys.get_state(pid).shutdown_initiated
    end

    test "triggers the shutdown action only once", ctx do
      start_manager(ctx)
      GenServer.cast(ShutdownManager, :heartbeat)

      assert_receive :shutdown_triggered, @timeout * 10
      # initiate_shutdown is idempotent: no further checks are scheduled.
      refute_receive :shutdown_triggered, @timeout * 4
    end
  end

  describe "cleanup" do
    test "removes the socket file on terminate", ctx do
      start_manager(ctx)
      assert wait_for_file(ctx.socket_path)

      :ok = stop_supervised(ShutdownManager)

      assert eventually(fn -> not File.exists?(ctx.socket_path) end)
    end
  end

  # The :tcp transport is what production uses on Windows, where the BEAM
  # cannot listen on Unix domain sockets. It is fully exercisable on any OS:
  # the manager listens on 127.0.0.1 and publishes the ephemeral port through
  # a discovery file that the Rust frontend polls.
  describe "tcp transport (Windows heartbeat path)" do
    setup ctx do
      port_file = port_file_for(ctx.app_name)
      on_exit(fn -> File.rm(port_file) end)
      %{port_file: port_file}
    end

    test "publishes the listener port in a discovery file", ctx do
      start_manager(ctx, transport: :tcp)

      assert wait_for_file(ctx.port_file)

      port = ctx.port_file |> File.read!() |> String.trim() |> String.to_integer()
      assert port in 1..65_535
    end

    test "accepts heartbeats over TCP and marks the frontend as connected", ctx do
      pid = start_manager(ctx, transport: :tcp)
      assert wait_for_file(ctx.port_file)

      client = tcp_connect(ctx.port_file)
      :ok = :gen_tcp.send(client, "h")

      assert eventually(fn -> :sys.get_state(pid).connected end)

      :gen_tcp.close(client)
    end

    test "shuts down once the TCP heartbeat is lost", ctx do
      start_manager(ctx, transport: :tcp)
      assert wait_for_file(ctx.port_file)

      client = tcp_connect(ctx.port_file)
      :ok = :gen_tcp.send(client, "h")
      :gen_tcp.close(client)

      assert_receive :shutdown_triggered, @timeout * 10
    end

    test "removes the port file on terminate", ctx do
      start_manager(ctx, transport: :tcp)
      assert wait_for_file(ctx.port_file)

      :ok = stop_supervised(ShutdownManager)

      assert eventually(fn -> not File.exists?(ctx.port_file) end)
    end

    test "cleans up a stale port file on startup", ctx do
      File.write!(ctx.port_file, "99999")

      pid = start_manager(ctx, transport: :tcp)

      assert Process.alive?(pid)
      assert wait_for_file(ctx.port_file)
      port = ctx.port_file |> File.read!() |> String.trim() |> String.to_integer()
      assert port in 1..65_535
    end
  end

  describe "configuration" do
    test "falls back to :app_name from config for the socket path" do
      app_name = "config_app_#{System.unique_integer([:positive])}"
      Application.put_env(:ex_tauri, :app_name, app_name)
      on_exit(fn -> Application.delete_env(:ex_tauri, :app_name) end)

      expected = socket_path_for(app_name)
      on_exit(fn -> File.rm(expected) end)

      # No :app_name opt, so the manager reads it from config.
      start_supervised!(
        {ShutdownManager,
         heartbeat_interval: @interval, heartbeat_timeout: @timeout, shutdown_fun: fn -> :ok end},
        restart: :temporary
      )

      assert wait_for_file(expected)
    end

    test "defaults :app_name to ex_tauri_app when not configured" do
      Application.delete_env(:ex_tauri, :app_name)
      expected = socket_path_for("ex_tauri_app")
      on_exit(fn -> File.rm(expected) end)

      start_supervised!(
        {ShutdownManager,
         heartbeat_interval: @interval, heartbeat_timeout: @timeout, shutdown_fun: fn -> :ok end},
        restart: :temporary
      )

      assert wait_for_file(expected)
    end
  end

  # --- helpers ---

  defp socket_path_for(app_name) do
    socket_name = ExTauri.Paths.sanitize_name(app_name)
    Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.sock")
  end

  defp connect(socket_path) do
    {:ok, client} = :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false])
    client
  end

  defp port_file_for(app_name) do
    socket_name = ExTauri.Paths.sanitize_name(app_name)
    Path.join(System.tmp_dir!(), "tauri_heartbeat_#{socket_name}.port")
  end

  defp tcp_connect(port_file) do
    port = port_file |> File.read!() |> String.trim() |> String.to_integer()
    {:ok, client} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, active: false])
    client
  end

  defp wait_for_file(path), do: eventually(fn -> File.exists?(path) end)

  # Polls a predicate until it returns true or the deadline passes. Replaces
  # fixed sleeps, which make tests both slow and timing-flaky.
  defp eventually(fun, attempts \\ 50, delay \\ 10)
  defp eventually(_fun, 0, _delay), do: false

  defp eventually(fun, attempts, delay) do
    if fun.() do
      true
    else
      Process.sleep(delay)
      eventually(fun, attempts - 1, delay)
    end
  end
end
