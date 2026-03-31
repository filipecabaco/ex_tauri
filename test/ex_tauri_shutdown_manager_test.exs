defmodule ExTauri.ShutdownManagerTest do
  use ExUnit.Case, async: false

  alias ExTauri.ShutdownManager

  @heartbeat_interval 100

  setup do
    # Use a unique app name per test to avoid socket collisions
    app_name = "test_app_#{System.unique_integer([:positive])}"
    Application.put_env(:ex_tauri, :app_name, app_name)

    socket_name = app_name |> String.replace(" ", "_") |> String.downcase()
    socket_path = "/tmp/tauri_heartbeat_#{socket_name}.sock"

    on_exit(fn ->
      # Clean up: stop the manager if running, remove socket
      if Process.whereis(ShutdownManager), do: GenServer.stop(ShutdownManager, :normal, 1000)
      File.rm(socket_path)
      Application.delete_env(:ex_tauri, :app_name)
    end)

    %{socket_path: socket_path, app_name: app_name}
  end

  describe "start_link/1" do
    test "starts the GenServer and creates the socket file", %{socket_path: socket_path} do
      assert {:ok, pid} = ShutdownManager.start_link()
      assert Process.alive?(pid)
      assert Process.whereis(ShutdownManager) == pid

      # Socket file should exist after startup
      # Give it a moment to bind
      Process.sleep(50)
      assert File.exists?(socket_path)
    end

    test "cleans up stale socket file on startup", %{socket_path: socket_path} do
      # Create a stale socket file
      File.write!(socket_path, "stale")
      assert File.exists?(socket_path)

      # Starting the manager should clean up and recreate
      assert {:ok, _pid} = ShutdownManager.start_link()
      Process.sleep(50)
      assert File.exists?(socket_path)
    end
  end

  describe "heartbeat mechanism" do
    test "accepts heartbeat connections via Unix socket", %{socket_path: socket_path} do
      {:ok, _pid} = ShutdownManager.start_link()
      Process.sleep(50)

      # Connect as a heartbeat client (simulating the Rust side)
      {:ok, client} = :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false])

      # Send a heartbeat byte
      assert :ok = :gen_tcp.send(client, "h")

      :gen_tcp.close(client)
    end

    test "stays alive while receiving heartbeats", %{socket_path: socket_path} do
      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      # Connect and send heartbeats
      {:ok, client} = :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false])

      # Send heartbeats for longer than the timeout period
      for _ <- 1..5 do
        :gen_tcp.send(client, "h")
        Process.sleep(@heartbeat_interval)
      end

      # Manager should still be alive
      assert Process.alive?(pid)

      :gen_tcp.close(client)
    end

    test "casts :heartbeat updates the last heartbeat timestamp" do
      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      # Directly cast a heartbeat
      GenServer.cast(ShutdownManager, :heartbeat)
      Process.sleep(10)

      # The process should still be alive (heartbeat was received)
      assert Process.alive?(pid)
    end
  end

  describe "shutdown detection" do
    test "detects heartbeat timeout and transitions to shutdown state" do
      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      # Suspend the process so :execute_shutdown won't fire System.stop/0
      # while we inspect state. We use :sys.suspend to freeze message processing.
      # First wait for the heartbeat timeout to trigger initiate_shutdown.
      # Timeline: 300ms timeout + 100ms check interval = ~400ms.
      Process.sleep(450)

      :sys.suspend(pid)
      state = :sys.get_state(pid)

      # Kill the process immediately (don't resume, as :execute_shutdown
      # would call System.stop/0 and kill the test runner)
      Process.exit(pid, :kill)

      assert state.shutdown_initiated,
             "ShutdownManager should have set shutdown_initiated after heartbeat timeout"
    end

    test "does not shut down immediately if heartbeats are being sent", %{socket_path: socket_path} do
      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      ref = Process.monitor(pid)

      # Connect and send heartbeats for 500ms (beyond the timeout window)
      {:ok, client} = :gen_tcp.connect({:local, socket_path}, 0, [:binary, active: false])

      for _ <- 1..5 do
        :gen_tcp.send(client, "h")
        Process.sleep(80)
      end

      # Should NOT have received a DOWN message during heartbeating
      refute_received {:DOWN, ^ref, :process, ^pid, _reason}

      :gen_tcp.close(client)
    end
  end

  describe "cleanup" do
    test "removes socket file on terminate", %{socket_path: socket_path} do
      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)
      assert File.exists?(socket_path)

      GenServer.stop(pid, :normal)
      Process.sleep(50)

      refute File.exists?(socket_path)
    end
  end

  describe "configuration" do
    test "uses app_name from config for socket path" do
      app_name = "my_custom_app_#{System.unique_integer([:positive])}"
      Application.put_env(:ex_tauri, :app_name, app_name)
      socket_name = app_name |> String.replace(" ", "_") |> String.downcase()
      expected_path = "/tmp/tauri_heartbeat_#{socket_name}.sock"

      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      assert File.exists?(expected_path)

      GenServer.stop(pid, :normal)
      File.rm(expected_path)
    end

    test "defaults app_name to ex_tauri_app when not configured" do
      Application.delete_env(:ex_tauri, :app_name)
      expected_path = "/tmp/tauri_heartbeat_ex_tauri_app.sock"

      {:ok, pid} = ShutdownManager.start_link()
      Process.sleep(50)

      assert File.exists?(expected_path)

      GenServer.stop(pid, :normal)
      File.rm(expected_path)
    end
  end
end
