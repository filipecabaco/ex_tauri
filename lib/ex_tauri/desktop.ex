defmodule ExTauri.Desktop do
  @moduledoc """
  Talk to the Tauri frontend from *server-side* Elixir — no LiveView required.

  The LiveView bridge (`ExTauri.Hook` and friends) needs a connected browser
  socket. This module instead uses the desktop channel that ExTauri maintains
  between the Phoenix sidecar and the Rust frontend (the same local socket that
  carries the shutdown heartbeat), so it works from GenServers, background
  jobs, PubSub handlers — anywhere in your application.

  ## Notifications from anywhere

      # In a background job, no LiveView involved:
      ExTauri.Desktop.notify("Sync complete", body: "128 records updated")

  ## System tray

  Define a tray icon and menu from Elixir. Clicks come back as events:

      ExTauri.Desktop.set_tray(
        tooltip: "My App",
        items: [
          %{id: "open", label: "Open"},
          %{id: "sync", label: "Sync now"},
          %{id: "quit", label: "Quit"}
        ]
      )

  ## Receiving native events

  Subscribe the calling process; events arrive as messages:

      def init(state) do
        ExTauri.Desktop.subscribe()
        {:ok, state}
      end

      def handle_info({:ex_tauri_event, "tray_menu_click", %{"id" => "sync"}}, state) do
        # user clicked "Sync now" in the tray menu
        {:noreply, do_sync(state)}
      end

      def handle_info({:ex_tauri_event, "tray_menu_click", %{"id" => "quit"}}, state) do
        # Tray ids are only ever forwarded here; quitting is asked for explicitly.
        ExTauri.Desktop.quit()
        {:noreply, state}
      end

  Event names include `"tray_menu_click"`, `"menu_click"` (application menu),
  `"heartbeat_late"` (the shell's heartbeat ran late — `%{"late_ms" => n}`, sent
  once when a stall starts, typically macOS App Nap throttling a hidden window;
  see `keep_awake/1`), and `"error"` (a command failed on the Rust side).

  ## Staying responsive in the background

  macOS App Nap slows the timers of an app whose window has been hidden for a
  while. Call `keep_awake(true)` while your app is doing work someone is waiting
  on, and `keep_awake(false)` when it is idle again — an app that holds it
  forever costs the user battery for nothing. The system can still sleep.

  ## Availability

  The channel exists once the Tauri frontend has connected (moments after the
  window appears). Before that — and always in plain `mix phx.server` runs
  outside Tauri — commands return `{:error, :not_connected}`. Callers should
  treat delivery as best-effort.
  """

  alias ExTauri.ShutdownManager

  @doc """
  Sends a native desktop notification from server-side code.

  ## Options

    * `:body` - The notification body text

  Returns `:ok`, or `{:error, :not_connected}` when the frontend isn't
  attached (e.g. running outside Tauri).
  """
  def notify(title, opts \\ []) when is_binary(title) do
    command("notify", %{title: title, body: opts[:body]})
  end

  @doc """
  Creates or replaces the system tray icon and its menu.

  ## Options

    * `:tooltip` - Hover text for the tray icon
    * `:items` - Menu items as maps with `:id` and `:label`

  Clicking a menu item delivers `{:ex_tauri_event, "tray_menu_click",
  %{"id" => id}}` to subscribed processes (see `subscribe/0`).
  """
  def set_tray(opts) when is_list(opts) do
    items =
      opts
      |> Keyword.get(:items, [])
      |> Enum.map(fn item -> %{id: to_string(item[:id]), label: to_string(item[:label])} end)

    command("set_tray", %{tooltip: opts[:tooltip], items: items})
  end

  @doc """
  Holds off macOS App Nap while `active` is true.

  The shell holds an `NSProcessInfo` activity for as long as the last call said
  `true`: timers keep their resolution with the window hidden, and the machine
  can still sleep when idle. A no-op on other platforms.

  Returns `:ok`, or `{:error, :not_connected}` before the frontend attaches —
  the shell keeps no memory of a call it never received, so callers that need
  it held should send it again once connected.
  """
  def keep_awake(active) when is_boolean(active) do
    command("keep_awake", %{active: active})
  end

  @doc """
  Asks the shell to quit the app the same way its Quit menu item does: the
  window goes, this backend is stopped gracefully, then the process exits.

  Returns `:ok`, or `{:error, :not_connected}` when there is no frontend.
  """
  def quit do
    command("quit", %{})
  end

  @doc """
  Subscribes the calling process to native desktop events.

  Events are delivered as `{:ex_tauri_event, name, payload}` messages. The
  subscription is monitored — it is cleaned up automatically when the caller
  exits.
  """
  def subscribe do
    call({:subscribe, self()})
  end

  @doc """
  Removes the calling process's event subscription.
  """
  def unsubscribe do
    call({:unsubscribe, self()})
  end

  defp command(name, payload) do
    call({:desktop_command, name, payload})
  end

  defp call(request) do
    case Process.whereis(ShutdownManager) do
      nil -> {:error, :not_running}
      pid -> GenServer.call(pid, request)
    end
  end
end
