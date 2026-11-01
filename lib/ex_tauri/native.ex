defmodule ExTauri.Native do
  @moduledoc """
  Channels between your Elixir code and native (Swift) plugins in the iOS app.

  Some of iOS is only reachable from Swift: Bluetooth, Multipeer Connectivity,
  HealthKit, the camera. `mix ex_tauri.ios plugin NAME` scaffolds a plugin whose
  Swift class opens the channel `NAME` to the BEAM through this module; with it in
  your supervision tree, Elixir and Swift exchange JSON over it:

      # application.ex
      children = [ExTauri.ShutdownManager, ExTauri.Native, ...]

      ExTauri.Native.subscribe("near-radio")
      # {:ex_tauri_native, "near-radio", :connected}       the plugin connected
      # {:ex_tauri_native, "near-radio", %{"op" => ...}}   a message from Swift
      # {:ex_tauri_native, "near-radio", :disconnected}

      ExTauri.Native.send("near-radio", %{"op" => "start"})

  ## How it connects

  The BEAM runs inside the app (see `mix ex_tauri.ios`), so a plugin reaches it
  over loopback. This listens on `127.0.0.1` at a free port, and writes the port
  and a token made at every launch to `handoff_path/0`, inside the app's container
  (mode 600); the plugin's `ExTauriNative.swift` reads them, connects, and must
  present the token first. Another app cannot read the file, so cannot connect.
  Messages are JSON, framed by a 4-byte big-endian length (`packet: 4`).

  It starts only where there is a native side to talk to, on iOS
  (`EX_TAURI_HOST_OS=ios`); elsewhere it is `:ignore`d, and `send/2` answers
  `{:error, :not_connected}`. Pass `enabled: true` to run it anyway.

  When the listener restarts (after a resume, see `ExTauri.Resume`, or a crash)
  every plugin is cut off: subscribers get `:disconnected`, then `:connected`
  again once the plugin has reconnected. A plugin that stops reading for 5 s is
  disconnected rather than left to block every `send/2`.

  Messages from a plugin are data, not commands: validate them as you would any
  input.
  """

  use GenServer
  require Logger
  import Kernel, except: [send: 2]

  @registry ExTauri.Native.Registry
  @max_frame 16 * 1024 * 1024
  @auth_timeout 5_000
  @send_timeout 5_000

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @doc false
  def start_link(opts \\ []) do
    if Keyword.get(opts, :enabled, System.get_env("EX_TAURI_HOST_OS") == "ios") do
      children = [
        {Registry, keys: :duplicate, name: @registry},
        %{id: :server, start: {GenServer, :start_link, [__MODULE__, opts, [name: __MODULE__]]}}
      ]

      Supervisor.start_link(children, strategy: :rest_for_one, name: ExTauri.Native.Supervisor)
    else
      :ignore
    end
  end

  @doc """
  Where the port and token are left for the native side: under the app's home
  (its container on iOS), the path `ExTauriNative.swift` derives the same way.
  """
  @spec handoff_path() :: Path.t()
  def handoff_path do
    home = System.get_env("EX_TAURI_HOME") || System.user_home!()
    Path.join([home, "Library", "Application Support", "ex_tauri", "native.json"])
  end

  @doc """
  Subscribes the calling process to `channel`. It receives
  `{:ex_tauri_native, channel, message}` for every message the plugin sends, and
  `:connected` / `:disconnected` in its place as the plugin comes and goes
  (`:connected` straight away when it is already).
  """
  @spec subscribe(String.t()) :: :ok | {:error, :not_running}
  def subscribe(channel) when is_binary(channel) do
    if Process.whereis(@registry) do
      {:ok, _} = Registry.register(@registry, channel, nil)
      if connected?(channel), do: Kernel.send(self(), {:ex_tauri_native, channel, :connected})
      :ok
    else
      {:error, :not_running}
    end
  end

  @doc """
  Sends a JSON-encodable value to the plugin on `channel`. A value Jason cannot
  encode is `{:error, exception}`.
  """
  @spec send(String.t(), term()) :: :ok | {:error, :not_connected | Exception.t()}
  def send(channel, data) when is_binary(channel) do
    # Encoded here, in the caller: a value that does not encode is the caller's
    # error, and raising inside the server would cut every plugin off. The call
    # outlasts a socket's send timeout, so a stalled plugin is dropped first.
    case Jason.encode_to_iodata(%{"channel" => channel, "data" => data}) do
      {:ok, frame} -> GenServer.call(__MODULE__, {:send, channel, frame}, @send_timeout * 2)
      {:error, _} = error -> error
    end
  catch
    :exit, _ -> {:error, :not_connected}
  end

  @doc "Whether a plugin is connected on `channel`."
  @spec connected?(String.t()) :: boolean()
  def connected?(channel) do
    GenServer.call(__MODULE__, {:connected?, channel})
  catch
    :exit, _ -> false
  end

  ## Server

  @impl true
  def init(opts) do
    # To tell subscribers the plugins are gone when it stops (terminate/2).
    Process.flag(:trap_exit, true)

    {:ok, listen} =
      :gen_tcp.listen(0, [
        :binary,
        packet: 4,
        packet_size: @max_frame,
        active: false,
        ip: {127, 0, 0, 1},
        reuseaddr: true
      ])

    {:ok, port} = :inet.port(listen)
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    :ok = write_handoff(port, token)

    # iOS may reclaim this socket while the app is suspended: listen again after,
    # with a new port and token the plugin reads on its next try.
    ExTauri.Resume.watch(__MODULE__, port, fn ->
      ExTauri.Resume.restart_child(ExTauri.Native.Supervisor, :server)
    end)

    server = self()
    acceptor = spawn_link(fn -> accept(listen, server) end)
    Logger.debug("[ExTauri.Native] listening on 127.0.0.1:#{port}")

    # socket => %{channels: [..] | :pending}
    {:ok,
     %{
       token: token,
       listen: listen,
       acceptor: acceptor,
       sockets: %{},
       send_timeout: Keyword.get(opts, :send_timeout, @send_timeout)
     }}
  end

  @impl true
  def handle_call({:send, channel, frame}, _from, s) do
    {sent, s} =
      Enum.reduce(sockets_for(s, channel), {false, s}, fn socket, {sent, s} ->
        case :gen_tcp.send(socket, frame) do
          :ok -> {true, s}
          {:error, _} -> {sent, close(socket, s)}
        end
      end)

    {:reply, if(sent, do: :ok, else: {:error, :not_connected}), s}
  end

  def handle_call({:connected?, channel}, _from, s),
    do: {:reply, sockets_for(s, channel) != [], s}

  @impl true
  def handle_info({:accepted, socket}, s) do
    # A plugin that stops reading would otherwise block this process in
    # :gen_tcp.send/2 for good, and every send/2 with it.
    case :inet.setopts(socket,
           active: :once,
           send_timeout: s.send_timeout,
           send_timeout_close: true
         ) do
      :ok ->
        Process.send_after(self(), {:auth_timeout, socket}, @auth_timeout)
        {:noreply, put_in(s.sockets[socket], %{channels: :pending})}

      {:error, _} ->
        :gen_tcp.close(socket)
        {:noreply, s}
    end
  end

  def handle_info({:tcp, socket, data}, s) do
    case s.sockets[socket] do
      %{channels: :pending} -> {:noreply, authenticate(socket, data, s)}
      %{channels: channels} -> {:noreply, message(socket, data, channels, s)}
      nil -> {:noreply, s}
    end
  end

  def handle_info({:tcp_closed, socket}, s), do: {:noreply, drop(socket, s)}
  def handle_info({:tcp_error, socket, _reason}, s), do: {:noreply, drop(socket, s)}

  def handle_info({:auth_timeout, socket}, s) do
    case s.sockets[socket] do
      %{channels: :pending} -> {:noreply, close(socket, s)}
      _ -> {:noreply, s}
    end
  end

  # The acceptor only stops when the listening socket is gone: start over.
  def handle_info({:EXIT, pid, reason}, %{acceptor: pid} = s), do: {:stop, reason, s}

  def handle_info(_msg, s), do: {:noreply, s}

  @impl true
  def terminate(_reason, s) do
    channels = for {_, %{channels: channels}} <- s.sockets, is_list(channels), do: channels

    # The registry may be what went down (rest_for_one restarts this after it).
    if Process.whereis(@registry) do
      for channel <- channels |> List.flatten() |> Enum.uniq(), do: notify(channel, :disconnected)
    end

    :ok
  end

  defp authenticate(socket, data, s) do
    with {:ok, %{"auth" => token, "channels" => channels}} <- Jason.decode(data),
         true <- same_token?(token, s.token),
         true <- is_list(channels) and channels != [] and Enum.all?(channels, &is_binary/1) do
      # The plugin may have gone already; then it never connected.
      with :ok <- :gen_tcp.send(socket, encode!(%{"ok" => true})),
           :ok <- :inet.setopts(socket, active: :once) do
        for channel <- channels, do: notify(channel, :connected)
        Logger.debug("[ExTauri.Native] connected: #{Enum.join(channels, ", ")}")
        put_in(s.sockets[socket], %{channels: channels})
      else
        {:error, _} -> close(socket, s)
      end
    else
      _ ->
        Logger.warning("[ExTauri.Native] refused a loopback connection without the token")
        close(socket, s)
    end
  end

  defp message(socket, data, channels, s) do
    with {:ok, %{"channel" => channel, "data" => message}} <- Jason.decode(data),
         true <- channel in channels do
      notify(channel, message)
    end

    case :inet.setopts(socket, active: :once) do
      :ok -> s
      {:error, _} -> close(socket, s)
    end
  end

  defp close(socket, s) do
    :gen_tcp.close(socket)
    drop(socket, s)
  end

  defp drop(socket, s) do
    case Map.pop(s.sockets, socket) do
      {%{channels: channels}, sockets} when is_list(channels) ->
        for channel <- channels, sockets_for(%{s | sockets: sockets}, channel) == [] do
          notify(channel, :disconnected)
        end

        %{s | sockets: sockets}

      {_, sockets} ->
        %{s | sockets: sockets}
    end
  end

  defp sockets_for(s, channel) do
    for {socket, %{channels: channels}} <- s.sockets,
        is_list(channels),
        channel in channels,
        do: socket
  end

  defp notify(channel, message) do
    Registry.dispatch(@registry, channel, fn subscribers ->
      for {pid, _} <- subscribers, do: Kernel.send(pid, {:ex_tauri_native, channel, message})
    end)
  end

  # In constant time: the token is the only thing between other code on the
  # device and the BEAM.
  defp same_token?(token, expected)
       when is_binary(token) and byte_size(token) == byte_size(expected),
       do: :crypto.hash_equals(token, expected)

  defp same_token?(_, _), do: false

  defp encode!(term), do: Jason.encode_to_iodata!(term)

  # Written aside and renamed over, readable by the app only: the file is made
  # 600 (in a 700 directory) before the token goes in, never after.
  defp write_handoff(port, token) do
    path = handoff_path()
    tmp = path <> ".tmp"
    File.mkdir_p!(Path.dirname(path))
    File.chmod!(Path.dirname(path), 0o700)
    File.rm(tmp)
    File.write!(tmp, "")
    File.chmod!(tmp, 0o600)
    File.write!(tmp, Jason.encode!(%{port: port, token: token}))
    File.rename(tmp, path)
  end

  defp accept(listen, server) do
    case :gen_tcp.accept(listen) do
      {:ok, socket} ->
        :ok = :gen_tcp.controlling_process(socket, server)
        Kernel.send(server, {:accepted, socket})
        accept(listen, server)

      {:error, reason} ->
        exit(reason)
    end
  end
end
