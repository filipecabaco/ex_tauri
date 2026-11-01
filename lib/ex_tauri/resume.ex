defmodule ExTauri.Resume do
  @moduledoc """
  Brings an app's listening sockets back after iOS suspended it.

  While an app is in the background iOS suspends it, and may reclaim its listening
  sockets meanwhile (Apple's TN2277, "Networking and Multitasking"). The BEAM is not
  told: it is frozen while it happens, and an `accept` waiting on a reclaimed socket
  simply never returns. So after the app comes back, its page cannot reach the
  backend (the window stays "connecting"), a native plugin cannot reconnect, and a
  peer dialling a server in the app is refused, until the app is quit and opened
  again.

  This notices the app was suspended (a timer due every `tick` ms fires minutes
  late), then checks every listener it was told about by connecting to it, and
  restarts the ones that refuse. ex_tauri starts it before your application, so
  there is nothing to add to your children, and `ExTauri.Native` watches its own.
  Watch your app's HTTP endpoint, whose loss is what leaves the window on
  "connecting", and anything else that listens, once your supervisor is up:

      # application.ex
      def start(_type, _args) do
        children = [ExTauri.ShutdownManager, ExTauri.Native, ..., MyApp.Router]
        {:ok, sup} = Supervisor.start_link(children, strategy: :one_for_one, name: MyApp.Supervisor)

        port = Application.fetch_env!(:ex_tauri, :port)

        ExTauri.Resume.watch(:http, port, fn ->
          ExTauri.Resume.restart_child(MyApp.Supervisor, MyApp.Router)
        end)

        ExTauri.Resume.on_resume(:links, fn _suspended_ms -> MyApp.reconnect() end)
        {:ok, sup}
      end

  It runs on every platform: a laptop that slept is resumed too, and checking a
  listener that is still there costs one loopback connection. Callbacks run one
  after another in a process of their own; one that raises is logged and skipped.
  """

  use GenServer
  require Logger

  @tick 2_000
  # Late by more than this, the app was suspended (or the machine slept), not busy.
  @late 5_000
  @connect_timeout 1_000

  # ex_tauri's supervisor starts it. An app that also lists it (as apps had to
  # before) gets `:ignore` instead of a crash, and the running one keeps its watches.
  @doc false
  def start_link(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: __MODULE__) do
      {:error, {:already_started, _}} -> :ignore
      other -> other
    end
  end

  @doc """
  Watches a listener on `port` (on loopback): after a resume, if nothing accepts
  there, `restart` is called to listen again. A later `watch` with the same `name`
  replaces this one. Does nothing if `ExTauri.Resume` is not running.
  """
  @spec watch(term(), :inet.port_number(), (-> term())) :: :ok
  def watch(name, port, restart) when is_integer(port) and is_function(restart, 0),
    do: register(name, {:listener, port, restart})

  @doc """
  Calls `fun` with how long the app was away (ms) after every resume, once the
  watched listeners are back. A later `on_resume` with the same `name` replaces it.
  """
  @spec on_resume(term(), (non_neg_integer() -> term())) :: :ok
  def on_resume(name, fun) when is_function(fun, 1), do: register(name, {:callback, fun})

  @doc "Stops and starts a supervisor's child again: the usual `restart` for `watch/3`."
  @spec restart_child(Supervisor.supervisor(), term()) :: term()
  def restart_child(supervisor, id) do
    _ = Supervisor.terminate_child(supervisor, id)
    Supervisor.restart_child(supervisor, id)
  end

  defp register(name, entry) do
    if Process.whereis(__MODULE__), do: GenServer.cast(__MODULE__, {:register, name, entry})
    :ok
  end

  @doc false
  # A tick due `tick` ms after `last` that came at `now`: more than `late` behind,
  # the BEAM was frozen (or the machine slept) rather than busy.
  @spec suspended(integer(), integer(), pos_integer(), non_neg_integer()) ::
          {:suspended, pos_integer()} | :awake
  def suspended(last, now, tick, late) do
    away = now - last - tick
    if away > late, do: {:suspended, away}, else: :awake
  end

  @impl true
  def init(opts) do
    tick = Keyword.get(opts, :tick, @tick)
    Process.send_after(self(), :tick, tick)

    {:ok,
     %{tick: tick, late: Keyword.get(opts, :late, @late), last: now(), watched: %{}, order: []}}
  end

  @impl true
  def handle_cast({:register, name, entry}, s) do
    order = if Map.has_key?(s.watched, name), do: s.order, else: s.order ++ [name]
    {:noreply, %{s | watched: Map.put(s.watched, name, entry), order: order}}
  end

  @impl true
  def handle_info(:tick, s) do
    Process.send_after(self(), :tick, s.tick)
    now = now()

    with {:suspended, away} <- suspended(s.last, now, s.tick, s.late) do
      Logger.info("ex_tauri: resumed after #{div(away, 1000)} s away; checking listeners")
      entries = for name <- s.order, do: {name, s.watched[name]}
      # Off this process: a restart may take a moment, and the ticks go on.
      Task.start(fn -> resume(entries, away) end)
    end

    {:noreply, %{s | last: now}}
  end

  def handle_info(_msg, s), do: {:noreply, s}

  # Listeners first, so what a callback reconnects finds them listening.
  defp resume(entries, away) do
    for {name, {:listener, port, restart}} <- entries, not listening?(port) do
      Logger.info("ex_tauri: #{inspect(name)} stopped listening on #{port}; restarting it")
      run(name, restart)
    end

    for {name, {:callback, fun}} <- entries, do: run(name, fn -> fun.(away) end)
  end

  defp run(name, fun) do
    fun.()
  rescue
    e -> Logger.error("ex_tauri: resume #{inspect(name)} failed: " <> Exception.message(e))
  catch
    kind, reason ->
      Logger.error("ex_tauri: resume #{inspect(name)} failed: #{inspect({kind, reason})}")
  end

  @doc false
  def listening?(port) do
    case :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false], @connect_timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  # Wall time, not monotonic: what matters is the time that passed outside the
  # BEAM, and a monotonic clock may stand still while the device sleeps.
  defp now, do: System.os_time(:millisecond)
end
