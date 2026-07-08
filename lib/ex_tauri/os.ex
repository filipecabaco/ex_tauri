defmodule ExTauri.OS do
  @moduledoc """
  Query OS information from your LiveView.

  Bridges to `tauri-plugin-os` via the LiveView hook.

  ## Requirements

  - `tauri-plugin-os` must be installed (see Plugin Setup below)
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)

  ## Plugin Setup

      mix ex_tauri.add os

  This adds the Cargo dependency, registers the plugin in `main.rs`, and adds
  the `os:default` capability. See `Mix.Tasks.ExTauri.Add` for details.

  ## Examples

      # Request OS info
      def handle_event("get_os_info", _params, socket) do
        socket = ExTauri.OS.info(socket)
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "os_info"} = params, socket) do
        os_info = %{
          platform: params["platform"],
          arch: params["arch"],
          version: params["version"],
          os_type: params["os_type"],
          locale: params["locale"]
        }
        {:noreply, assign(socket, :os_info, os_info)}
      end
  """

  @doc """
  Requests OS information from the Tauri runtime.

  The result will be sent back as a `"tauri_response"` event with fields:
  `platform`, `arch`, `version`, `os_type`, and `locale`.

  ## Examples

      ExTauri.OS.info(socket)
  """
  def info(socket) do
    ExTauri.Hook.push_command(socket, "os_info", %{})
  end
end
