defmodule ExTauri.Window do
  @moduledoc """
  Manage the native window at runtime from your LiveView.

  Bridges to Tauri's core window API via the LiveView hook — no extra plugin
  is required. Minimize, maximize, resize, retitle, or hide the window in
  response to your application's state.

  ## Requirements

  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)
  - Window permissions in `src-tauri/capabilities/default.json`. Projects
    created by current versions of `mix ex_tauri.install` already include
    them; older projects can add them with:

        mix ex_tauri.add window

  ## Examples

      # Update the window title to reflect the open document
      def handle_event("select_doc", %{"name" => name}, socket) do
        socket = ExTauri.Window.set_title(socket, "\#{name} — MyApp")
        {:noreply, assign(socket, :doc, name)}
      end

      # Toggle fullscreen from a button
      def handle_event("toggle_fullscreen", _params, socket) do
        fullscreen? = !socket.assigns.fullscreen
        socket = ExTauri.Window.set_fullscreen(socket, fullscreen?)
        {:noreply, assign(socket, :fullscreen, fullscreen?)}
      end

      # Query window state
      def handle_event("check_window", _params, socket) do
        {:noreply, ExTauri.Window.info(socket)}
      end

      def handle_event("tauri_response", %{"command" => "window", "title" => _} = params, socket) do
        {:noreply, assign(socket, :window_info, params)}
      end
  """

  alias ExTauri.Hook

  @doc "Minimizes the window."
  def minimize(socket), do: action(socket, "minimize")

  @doc "Maximizes the window."
  def maximize(socket), do: action(socket, "maximize")

  @doc "Restores the window from the maximized state."
  def unmaximize(socket), do: action(socket, "unmaximize")

  @doc "Toggles between maximized and windowed state."
  def toggle_maximize(socket), do: action(socket, "toggle_maximize")

  @doc "Enters or leaves fullscreen."
  def set_fullscreen(socket, fullscreen?) when is_boolean(fullscreen?) do
    action(socket, "set_fullscreen", %{fullscreen: fullscreen?})
  end

  @doc "Sets the window title."
  def set_title(socket, title) when is_binary(title) do
    action(socket, "set_title", %{title: title})
  end

  @doc "Resizes the window to the given logical width and height (pixels)."
  def set_size(socket, width, height)
      when is_number(width) and width > 0 and is_number(height) and height > 0 do
    action(socket, "set_size", %{width: width, height: height})
  end

  @doc "Centers the window on the current monitor."
  def center(socket), do: action(socket, "center")

  @doc "Brings the window to the front and focuses it."
  def focus(socket), do: action(socket, "set_focus")

  @doc "Hides the window (it keeps running; use `show/1` to bring it back)."
  def hide(socket), do: action(socket, "hide")

  @doc "Shows a previously hidden window."
  def show(socket), do: action(socket, "show")

  @doc "Keeps the window above all others (or stops doing so)."
  def set_always_on_top(socket, on_top?) when is_boolean(on_top?) do
    action(socket, "set_always_on_top", %{value: on_top?})
  end

  @doc "Allows or prevents window resizing."
  def set_resizable(socket, resizable?) when is_boolean(resizable?) do
    action(socket, "set_resizable", %{value: resizable?})
  end

  @doc """
  Starts dragging the window, for custom titlebars.

  Call this from a `phx-click` (or `mousedown`-driven event) on your custom
  titlebar element to let users move a window with no native decorations.
  """
  def start_dragging(socket), do: action(socket, "start_dragging")

  @doc """
  Requests the current window state.

  The result arrives as a `"tauri_response"` event with `%{"command" => "window",
  "title" => ..., "is_maximized" => ..., "is_minimized" => ..., "is_fullscreen" => ...,
  "is_focused" => ..., "scale_factor" => ...}`.
  """
  def info(socket), do: action(socket, "info")

  defp action(socket, action, payload \\ %{}) do
    Hook.push_command(socket, "window", Map.put(payload, :action, action))
  end
end
