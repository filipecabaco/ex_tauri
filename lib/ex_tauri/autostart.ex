defmodule ExTauri.Autostart do
  @moduledoc """
  Control launch-at-login from your LiveView.

  Bridges to `tauri-plugin-autostart` via the LiveView hook.

  ## Plugin Setup

      mix ex_tauri.add autostart

  ## Examples

      # A settings toggle
      def handle_event("toggle_autostart", %{"enabled" => "true"}, socket) do
        {:noreply, ExTauri.Autostart.enable(socket)}
      end

      def handle_event("toggle_autostart", _params, socket) do
        {:noreply, ExTauri.Autostart.disable(socket)}
      end

      # Read the current state when the settings page mounts
      def handle_event("load_settings", _params, socket) do
        {:noreply, ExTauri.Autostart.status(socket)}
      end

      def handle_event("tauri_response", %{"command" => "autostart_status", "enabled" => enabled}, socket) do
        {:noreply, assign(socket, :autostart_enabled, enabled)}
      end
  """

  alias ExTauri.Hook

  @doc "Enables launching the app at login."
  def enable(socket) do
    Hook.push_command(socket, "autostart_enable", %{})
  end

  @doc "Disables launching the app at login."
  def disable(socket) do
    Hook.push_command(socket, "autostart_disable", %{})
  end

  @doc """
  Queries whether launch-at-login is enabled.

  The result arrives as a `"tauri_response"` event with
  `%{"command" => "autostart_status", "enabled" => true | false}`.
  """
  def status(socket) do
    Hook.push_command(socket, "autostart_status", %{})
  end
end
