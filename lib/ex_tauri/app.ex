defmodule ExTauri.App do
  @moduledoc """
  Query application info and control the app lifecycle from your LiveView.

  `info/1` uses Tauri's core app API and works out of the box. `exit/2` and
  `relaunch/1` bridge to `tauri-plugin-process`, installed with:

      mix ex_tauri.add process

  ## Examples

      # Show the app version in an "About" panel
      def handle_event("about", _params, socket) do
        {:noreply, ExTauri.App.info(socket)}
      end

      def handle_event("tauri_response", %{"command" => "app_info"} = params, socket) do
        {:noreply, assign(socket, :about, params)}
      end

      # Restart after applying settings that need a fresh boot
      def handle_event("apply_and_restart", _params, socket) do
        {:noreply, ExTauri.App.relaunch(socket)}
      end
  """

  alias ExTauri.Hook

  @doc """
  Requests the application name and version.

  The result arrives as a `"tauri_response"` event with
  `%{"command" => "app_info", "name" => ..., "version" => ..., "tauri_version" => ...}`.
  """
  def info(socket) do
    Hook.push_command(socket, "app_info", %{})
  end

  @doc """
  Exits the application with the given status code (default 0).

  Requires `tauri-plugin-process` (`mix ex_tauri.add process`). This closes the
  Tauri frontend; the Phoenix sidecar then shuts down via the heartbeat.
  """
  def exit(socket, code \\ 0) when is_integer(code) do
    Hook.push_command(socket, "process_exit", %{code: code})
  end

  @doc """
  Exits and relaunches the application.

  Requires `tauri-plugin-process` (`mix ex_tauri.add process`).
  """
  def relaunch(socket) do
    Hook.push_command(socket, "process_relaunch", %{})
  end
end
