defmodule ExTauri.Notification do
  @moduledoc """
  Send native desktop notifications from your LiveView.

  This module provides a simple API for sending OS-native notifications
  via the Tauri notification plugin, bridged through the LiveView hook.

  ## Requirements

  - `tauri-plugin-notification` must be installed (added by `mix ex_tauri.install`)
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)
  - The `notification:default` capability must be configured

  ## Examples

      # In a LiveView
      def handle_event("save", _params, socket) do
        # ... save logic ...
        socket = ExTauri.Notification.send(socket, "Saved!", body: "Your changes have been saved.")
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "notification"} = params, socket) do
        case params["status"] do
          "sent" -> {:noreply, socket}
          "denied" -> {:noreply, put_flash(socket, :error, "Notification permission denied")}
        end
      end
  """

  @doc """
  Sends a native desktop notification.

  ## Options

    * `:body` - The notification body text
    * `:icon` - Path to a notification icon

  ## Examples

      ExTauri.Notification.send(socket, "Download Complete")
      ExTauri.Notification.send(socket, "New Message", body: "You have 3 new messages")
  """
  def send(socket, title, opts \\ []) do
    payload =
      %{title: title}
      |> maybe_put(:body, opts[:body])
      |> maybe_put(:icon, opts[:icon])

    ExTauri.Hook.push_command(socket, "notification", payload)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
