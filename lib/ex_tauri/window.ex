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
  def minimize(socket, on_reply \\ nil), do: action(socket, "minimize", %{}, on_reply)

  @doc "Maximizes the window."
  def maximize(socket, on_reply \\ nil), do: action(socket, "maximize", %{}, on_reply)

  @doc "Restores the window from the maximized state."
  def unmaximize(socket, on_reply \\ nil), do: action(socket, "unmaximize", %{}, on_reply)

  @doc "Toggles between maximized and windowed state."
  def toggle_maximize(socket, on_reply \\ nil),
    do: action(socket, "toggle_maximize", %{}, on_reply)

  @doc "Enters or leaves fullscreen."
  def set_fullscreen(socket, fullscreen?, on_reply \\ nil) when is_boolean(fullscreen?) do
    action(socket, "set_fullscreen", %{fullscreen: fullscreen?}, on_reply)
  end

  @doc "Sets the window title."
  def set_title(socket, title, on_reply \\ nil) when is_binary(title) do
    action(socket, "set_title", %{title: title}, on_reply)
  end

  @doc "Resizes the window to the given logical width and height (pixels)."
  def set_size(socket, width, height, on_reply \\ nil)
      when is_number(width) and width > 0 and is_number(height) and height > 0 do
    action(socket, "set_size", %{width: width, height: height}, on_reply)
  end

  @doc "Centers the window on the current monitor."
  def center(socket, on_reply \\ nil), do: action(socket, "center", %{}, on_reply)

  @doc "Brings the window to the front and focuses it."
  def focus(socket, on_reply \\ nil), do: action(socket, "set_focus", %{}, on_reply)

  @doc "Hides the window (it keeps running; use `show/1` to bring it back)."
  def hide(socket, on_reply \\ nil), do: action(socket, "hide", %{}, on_reply)

  @doc "Shows a previously hidden window."
  def show(socket, on_reply \\ nil), do: action(socket, "show", %{}, on_reply)

  @doc "Keeps the window above all others (or stops doing so)."
  def set_always_on_top(socket, on_top?, on_reply \\ nil) when is_boolean(on_top?) do
    action(socket, "set_always_on_top", %{value: on_top?}, on_reply)
  end

  @doc "Allows or prevents window resizing."
  def set_resizable(socket, resizable?, on_reply \\ nil) when is_boolean(resizable?) do
    action(socket, "set_resizable", %{value: resizable?}, on_reply)
  end

  @doc """
  Starts dragging the window, for custom titlebars.

  Call this from a `phx-click` (or `mousedown`-driven event) on your custom
  titlebar element to let users move a window with no native decorations.
  """
  def start_dragging(socket, on_reply \\ nil), do: action(socket, "start_dragging", %{}, on_reply)

  @doc """
  Requests the current window state.

  The result arrives as a `"tauri_response"` event with `%{"command" => "window",
  "title" => ..., "is_maximized" => ..., "is_minimized" => ..., "is_fullscreen" => ...,
  "is_focused" => ..., "scale_factor" => ...}`.
  """
  def info(socket, on_reply \\ nil), do: action(socket, "info", %{}, on_reply)

  @doc """
  Opens a new window rendering the given path of your Phoenix app.

  The `label` uniquely identifies the window (used by `close/3`). `path` is
  resolved against the app's origin (e.g. `"/settings"`).

  ## Options

    * `:title` - Window title
    * `:width` / `:height` - Initial logical size (both required to apply)
    * `:resizable` - Allow resizing (default: true)

  ## Examples

      ExTauri.Window.open(socket, "settings", "/settings", title: "Settings", width: 500, height: 400)
  """
  def open(socket, label, path, opts \\ [], on_reply \\ nil)
      when is_binary(label) and is_binary(path) do
    payload =
      %{label: label, url: path}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:width, opts[:width])
      |> maybe_put(:height, opts[:height])
      |> maybe_put(:resizable, opts[:resizable])

    Hook.push_command(socket, "window_open", payload, on_reply)
  end

  @doc """
  Closes a window previously opened with `open/5`, by label.
  """
  def close(socket, label, on_reply \\ nil) when is_binary(label) do
    Hook.push_command(socket, "window_close", %{label: label}, on_reply)
  end

  defp action(socket, action, payload, on_reply) do
    Hook.push_command(socket, "window", Map.put(payload, :action, action), on_reply)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
