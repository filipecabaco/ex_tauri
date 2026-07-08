defmodule ExTauri.Clipboard do
  @moduledoc """
  Read and write the system clipboard from your LiveView.

  Bridges to `tauri-plugin-clipboard-manager` via the LiveView hook.

  ## Requirements

  - `tauri-plugin-clipboard-manager` must be installed (see Plugin Setup below)
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)

  ## Plugin Setup

      mix ex_tauri.add clipboard

  This adds the Cargo dependency, registers the plugin in `main.rs`, and adds
  the read/write-text capabilities. See `Mix.Tasks.ExTauri.Add` for details.

  ## Examples

      # Write to clipboard
      def handle_event("copy", %{"text" => text}, socket) do
        socket = ExTauri.Clipboard.write(socket, text)
        {:noreply, socket}
      end

      # Read from clipboard
      def handle_event("paste", _params, socket) do
        socket = ExTauri.Clipboard.read(socket)
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "clipboard_read", "text" => text}, socket) do
        {:noreply, assign(socket, :clipboard_text, text)}
      end
  """

  @doc """
  Writes text to the system clipboard.

  ## Examples

      ExTauri.Clipboard.write(socket, "Hello, clipboard!")
  """
  def write(socket, text, on_reply \\ nil) do
    ExTauri.Hook.push_command(socket, "clipboard_write", %{text: text}, on_reply)
  end

  @doc """
  Reads text from the system clipboard.

  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "clipboard_read", "text" => "..."}`.

  ## Examples

      ExTauri.Clipboard.read(socket)
  """
  def read(socket, on_reply \\ nil) do
    ExTauri.Hook.push_command(socket, "clipboard_read", %{}, on_reply)
  end
end
