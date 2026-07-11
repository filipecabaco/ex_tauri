defmodule ExTauri.DesktopTest do
  use ExUnit.Case, async: false

  alias ExTauri.Desktop
  alias ExTauri.ShutdownManager

  # Exercises the duplex desktop channel over the same socket the heartbeat
  # uses: this test plays the Rust frontend's role with a plain gen_tcp client.

  @interval 50
  @timeout 150

  setup do
    app_name = "desktop_test_#{System.unique_integer([:positive])}"
    socket_path = socket_path_for(app_name)
    on_exit(fn -> File.rm(socket_path) end)

    test_pid = self()

    start_supervised!(
      {ShutdownManager,
       app_name: app_name,
       heartbeat_interval: @interval,
       heartbeat_timeout: @timeout,
       shutdown_fun: fn -> send(test_pid, :shutdown_triggered) end},
      restart: :temporary
    )

    assert eventually(fn -> File.exists?(socket_path) end)

    %{socket_path: socket_path}
  end

  describe "channel protocol (frontend -> Elixir)" do
    test "JSON heartbeat lines count as heartbeats", ctx do
      client = connect(ctx.socket_path)
      :ok = :gen_tcp.send(client, ~s({"type":"heartbeat"}\n))

      pid = Process.whereis(ShutdownManager)
      assert eventually(fn -> :sys.get_state(pid).connected end)

      :gen_tcp.close(client)
    end

    test "event lines are delivered to subscribed processes", ctx do
      :ok = Desktop.subscribe()
      client = connect(ctx.socket_path)

      line = Jason.encode!(%{type: "event", name: "tray_menu_click", payload: %{"id" => "sync"}})
      :ok = :gen_tcp.send(client, line <> "\n")

      assert_receive {:ex_tauri_event, "tray_menu_click", %{"id" => "sync"}}, 2_000

      :gen_tcp.close(client)
      Desktop.unsubscribe()
    end

    test "events split across TCP packets are reassembled", ctx do
      :ok = Desktop.subscribe()
      client = connect(ctx.socket_path)

      line = Jason.encode!(%{type: "event", name: "menu_click", payload: %{"id" => "a"}}) <> "\n"
      {first, second} = String.split_at(line, 10)

      :ok = :gen_tcp.send(client, first)
      Process.sleep(20)
      :ok = :gen_tcp.send(client, second)

      assert_receive {:ex_tauri_event, "menu_click", %{"id" => "a"}}, 2_000

      :gen_tcp.close(client)
      Desktop.unsubscribe()
    end

    test "unsubscribed processes stop receiving events", ctx do
      :ok = Desktop.subscribe()
      :ok = Desktop.unsubscribe()

      client = connect(ctx.socket_path)
      line = Jason.encode!(%{type: "event", name: "menu_click", payload: %{}})
      :ok = :gen_tcp.send(client, line <> "\n")

      refute_receive {:ex_tauri_event, _, _}, 300

      :gen_tcp.close(client)
    end
  end

  describe "desktop commands (Elixir -> frontend)" do
    test "notify returns not_connected without a frontend" do
      assert {:error, :not_connected} = Desktop.notify("Hello")
    end

    test "notify reaches the connected frontend as a JSON command", ctx do
      client = connect(ctx.socket_path)

      # The manager registers the client asynchronously; retry until it has.
      assert eventually(fn -> Desktop.notify("Hello", body: "World") == :ok end)

      assert {:ok, line} = recv_line(client)

      assert %{
               "type" => "command",
               "name" => "notify",
               "payload" => %{"title" => "Hello", "body" => "World"}
             } = Jason.decode!(line)

      :gen_tcp.close(client)
    end

    test "set_tray serializes tooltip and items", ctx do
      client = connect(ctx.socket_path)

      assert eventually(fn ->
               Desktop.set_tray(
                 tooltip: "My App",
                 items: [%{id: "open", label: "Open"}, %{id: :quit, label: "Quit"}]
               ) == :ok
             end)

      assert {:ok, line} = recv_line(client)

      assert %{
               "type" => "command",
               "name" => "set_tray",
               "payload" => %{
                 "tooltip" => "My App",
                 "items" => [
                   %{"id" => "open", "label" => "Open"},
                   %{"id" => "quit", "label" => "Quit"}
                 ]
               }
             } = Jason.decode!(line)

      :gen_tcp.close(client)
    end

    test "commands fail again after the frontend disconnects", ctx do
      client = connect(ctx.socket_path)
      assert eventually(fn -> Desktop.notify("Hi") == :ok end)

      :gen_tcp.close(client)

      assert eventually(fn -> Desktop.notify("Hi") == {:error, :not_connected} end)
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

  # Reads until a full line arrives (commands are newline-delimited JSON).
  defp recv_line(client, acc \\ "") do
    if String.contains?(acc, "\n") do
      [line | _rest] = String.split(acc, "\n")
      {:ok, line}
    else
      case :gen_tcp.recv(client, 0, 2_000) do
        {:ok, data} -> recv_line(client, acc <> data)
        {:error, reason} -> {:error, reason}
      end
    end
  end

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
