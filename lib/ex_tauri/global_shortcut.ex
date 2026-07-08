defmodule ExTauri.GlobalShortcut do
  @moduledoc """
  Register app-wide keyboard shortcuts from your LiveView.

  Bridges to `tauri-plugin-global-shortcut` via the LiveView hook. Global
  shortcuts fire even when the window is not focused — ideal for
  show/hide-the-app hotkeys or media-style controls.

  ## Plugin Setup

      mix ex_tauri.add global-shortcut

  ## Shortcut format

  Shortcuts use the standard accelerator syntax, e.g. `"CommandOrControl+Shift+K"`,
  `"Alt+Space"`, `"F11"`.

  ## Examples

      # Register on mount
      def mount(_params, _session, socket) do
        socket =
          if connected?(socket) do
            ExTauri.GlobalShortcut.register(socket, "CommandOrControl+Shift+K")
          else
            socket
          end

        {:ok, socket}
      end

      # Every press/release arrives as a "tauri_event"
      def handle_event(
            "tauri_event",
            %{"event" => "global_shortcut", "shortcut" => shortcut, "state" => "Pressed"},
            socket
          ) do
        {:noreply, put_flash(socket, :info, "\#{shortcut} pressed!")}
      end

      def handle_event("tauri_event", _params, socket), do: {:noreply, socket}

  ## Lifecycle note

  Global shortcuts are registered with the OS and stay active until
  unregistered or the app exits — they are not cleaned up on LiveView
  navigation. Unregister explicitly when the shortcut should stop applying.
  """

  alias ExTauri.Hook

  @doc """
  Registers a global shortcut.

  Confirmation arrives as a `"tauri_response"` with
  `%{"command" => "shortcut_register", "status" => "ok"}`. Presses/releases are
  delivered as `"tauri_event"` events with
  `%{"event" => "global_shortcut", "shortcut" => ..., "state" => "Pressed" | "Released"}`.

  Registering a shortcut that is already registered (by this app or another)
  fails with a `"tauri_error"` event.
  """
  def register(socket, shortcut) when is_binary(shortcut) do
    Hook.push_command(socket, "shortcut_register", %{shortcut: shortcut})
  end

  @doc """
  Unregisters a previously registered global shortcut.
  """
  def unregister(socket, shortcut) when is_binary(shortcut) do
    Hook.push_command(socket, "shortcut_unregister", %{shortcut: shortcut})
  end

  @doc """
  Checks whether a shortcut is currently registered.

  The result arrives as a `"tauri_response"` with
  `%{"command" => "shortcut_is_registered", "registered" => true | false}`.
  """
  def registered?(socket, shortcut) when is_binary(shortcut) do
    Hook.push_command(socket, "shortcut_is_registered", %{shortcut: shortcut})
  end
end
