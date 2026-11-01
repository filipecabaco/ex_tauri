defmodule ExTauri.NativeTest do
  use ExUnit.Case, async: false

  alias ExTauri.Native

  setup do
    home = Path.join(System.tmp_dir!(), "ex_tauri_native_#{System.unique_integer([:positive])}")
    System.put_env("EX_TAURI_HOME", home)
    # A short send timeout, for the plugin that stops reading.
    start_supervised!({Native, enabled: true, send_timeout: 200})

    on_exit(fn ->
      System.delete_env("EX_TAURI_HOME")
      File.rm_rf!(home)
    end)

    %{handoff: Native.handoff_path() |> File.read!() |> Jason.decode!()}
  end

  # What ExTauriNative.swift does: connect, present the token and its channels.
  defp plugin(%{"port" => port, "token" => token}, channels, auth \\ nil) do
    {:ok, socket} = :gen_tcp.connect({127, 0, 0, 1}, port, [:binary, packet: 4, active: false])
    :ok = :gen_tcp.send(socket, Jason.encode!(%{auth: auth || token, channels: channels}))
    socket
  end

  defp recv!(socket), do: socket |> :gen_tcp.recv(0, 1_000) |> elem(1) |> Jason.decode!()

  test "is :ignore'd away from iOS" do
    assert Native.start_link() == :ignore
  end

  test "the handoff is the app's alone", %{handoff: handoff} do
    assert %{"port" => port, "token" => token} = handoff
    assert is_integer(port) and byte_size(token) >= 32
    assert %{mode: mode} = File.stat!(Native.handoff_path())
    assert Bitwise.band(mode, 0o077) == 0
  end

  test "a plugin with the token exchanges messages on its channel", %{handoff: handoff} do
    :ok = Native.subscribe("radio")
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    assert_receive {:ex_tauri_native, "radio", :connected}

    :ok = :gen_tcp.send(socket, Jason.encode!(%{channel: "radio", data: %{"op" => "up"}}))
    assert_receive {:ex_tauri_native, "radio", %{"op" => "up"}}

    assert :ok = Native.send("radio", %{"op" => "send"})
    assert recv!(socket) == %{"channel" => "radio", "data" => %{"op" => "send"}}

    :gen_tcp.close(socket)
    assert_receive {:ex_tauri_native, "radio", :disconnected}
    assert {:error, :not_connected} = Native.send("radio", %{})
  end

  test "without the token, nothing gets through", %{handoff: handoff} do
    :ok = Native.subscribe("radio")
    socket = plugin(handoff, ["radio"], "guess")
    assert {:error, :closed} = :gen_tcp.recv(socket, 0, 1_000)
    refute_received {:ex_tauri_native, "radio", _}
    refute Native.connected?("radio")
  end

  test "a plugin speaks only on the channels it opened", %{handoff: handoff} do
    :ok = Native.subscribe("other")
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    :ok = :gen_tcp.send(socket, Jason.encode!(%{channel: "other", data: 1}))
    refute_receive {:ex_tauri_native, "other", 1}, 200
  end

  test "subscribing late still learns the plugin is there", %{handoff: handoff} do
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    :ok = Native.subscribe("radio")
    assert_receive {:ex_tauri_native, "radio", :connected}
  end

  test "a value that does not encode is the caller's error; the bridge carries on",
       %{handoff: handoff} do
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    server = Process.whereis(Native)

    assert {:error, %Protocol.UndefinedError{}} = Native.send("radio", %{"pid" => self()})
    assert Process.whereis(Native) == server
    assert :ok = Native.send("radio", 1)
    assert recv!(socket) == %{"channel" => "radio", "data" => 1}
  end

  test "a plugin that leaves at once does not take the bridge down", %{handoff: handoff} do
    server = Process.whereis(Native)

    for _ <- 1..20 do
      handoff |> plugin(["radio"]) |> :gen_tcp.close()
      {:ok, bare} = :gen_tcp.connect({127, 0, 0, 1}, handoff["port"], [:binary, packet: 4])
      :gen_tcp.close(bare)
    end

    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    assert Process.whereis(Native) == server
  end

  test "a plugin that stops reading is dropped, not waited on", %{handoff: handoff} do
    :ok = Native.subscribe("radio")
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    assert_receive {:ex_tauri_native, "radio", :connected}
    server = Process.whereis(Native)

    # Never read: the socket buffers fill, and a send waits out its timeout.
    chunk = String.duplicate("x", 1024 * 1024)
    results = Enum.map(1..64, fn _ -> Native.send("radio", chunk) end)

    assert {:error, :not_connected} in results
    assert_receive {:ex_tauri_native, "radio", :disconnected}
    assert Process.whereis(Native) == server
    :gen_tcp.close(socket)
  end

  test "subscribers hear :disconnected when the bridge restarts", %{handoff: handoff} do
    :ok = Native.subscribe("radio")
    socket = plugin(handoff, ["radio"])
    assert recv!(socket) == %{"ok" => true}
    assert_receive {:ex_tauri_native, "radio", :connected}

    ExTauri.Resume.restart_child(ExTauri.Native.Supervisor, :server)
    assert_receive {:ex_tauri_native, "radio", :disconnected}
  end
end
