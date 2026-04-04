defmodule ExTauri.Dialog do
  @moduledoc """
  Open native file and message dialogs from your LiveView.

  Bridges to `tauri-plugin-dialog` via the LiveView hook.

  ## Requirements

  - `tauri-plugin-dialog` must be installed (see Plugin Setup below)
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)

  ## Plugin Setup

  Add the dependency to `src-tauri/Cargo.toml`:

      [dependencies]
      tauri-plugin-dialog = "2"

  Register the plugin in `src-tauri/src/main.rs` inside `tauri::Builder`:

      .plugin(tauri_plugin_dialog::init())

  Add the capability to `src-tauri/capabilities/default.json`:

      "permissions": ["dialog:default"]

  ## Examples

      # Open file picker
      def handle_event("open_file", _params, socket) do
        socket = ExTauri.Dialog.open(socket, title: "Select a file")
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "dialog_open", "path" => path}, socket) do
        {:noreply, assign(socket, :selected_file, path)}
      end
  """

  @doc """
  Opens a file selection dialog.

  ## Options

    * `:title` - Dialog window title
    * `:default_path` - Starting directory or file path
    * `:multiple` - Allow selecting multiple files (default: false)
    * `:directory` - Select directories instead of files (default: false)
    * `:filters` - List of file filters, e.g. `[%{name: "Images", extensions: ["png", "jpg"]}]`

  ## Examples

      ExTauri.Dialog.open(socket, title: "Select an image", filters: [%{name: "Images", extensions: ["png", "jpg"]}])
      ExTauri.Dialog.open(socket, directory: true, title: "Select folder")
  """
  def open(socket, opts \\ []) do
    payload =
      %{}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:defaultPath, opts[:default_path])
      |> maybe_put(:multiple, opts[:multiple])
      |> maybe_put(:directory, opts[:directory])
      |> maybe_put(:filters, opts[:filters])

    ExTauri.Hook.push_command(socket, "dialog_open", payload)
  end

  @doc """
  Opens a file save dialog.

  ## Options

    * `:title` - Dialog window title
    * `:default_path` - Starting directory or default file name
    * `:filters` - List of file filters

  ## Examples

      ExTauri.Dialog.save(socket, title: "Save as", default_path: "document.txt")
  """
  def save(socket, opts \\ []) do
    payload =
      %{}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:defaultPath, opts[:default_path])
      |> maybe_put(:filters, opts[:filters])

    ExTauri.Hook.push_command(socket, "dialog_save", payload)
  end

  @doc """
  Shows a message dialog (alert).

  ## Options

    * `:title` - Dialog window title
    * `:ok_label` - Custom label for the OK button

  ## Examples

      ExTauri.Dialog.message(socket, "Operation completed successfully!")
  """
  def message(socket, message, opts \\ []) do
    payload =
      %{message: message}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:okLabel, opts[:ok_label])

    ExTauri.Hook.push_command(socket, "dialog_message", payload)
  end

  @doc """
  Shows a confirmation dialog with Yes/No buttons.

  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "dialog_message", "result" => true | false}`.

  ## Options

    * `:title` - Dialog window title
    * `:ok_label` - Custom label for the OK/Yes button
    * `:cancel_label` - Custom label for the Cancel/No button

  ## Examples

      ExTauri.Dialog.confirm(socket, "Are you sure you want to delete this?")
  """
  def confirm(socket, message, opts \\ []) do
    payload =
      %{message: message, type: "confirm"}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:okLabel, opts[:ok_label])
      |> maybe_put(:cancelLabel, opts[:cancel_label])

    ExTauri.Hook.push_command(socket, "dialog_message", payload)
  end

  @doc """
  Shows an ask dialog with Yes/No buttons.

  Similar to `confirm/3` but uses Tauri's `ask` dialog variant.

  ## Options

    * `:title` - Dialog window title
    * `:ok_label` - Custom label for the OK/Yes button
    * `:cancel_label` - Custom label for the Cancel/No button

  ## Examples

      ExTauri.Dialog.ask(socket, "Do you want to save changes before closing?")
  """
  def ask(socket, message, opts \\ []) do
    payload =
      %{message: message, type: "ask"}
      |> maybe_put(:title, opts[:title])
      |> maybe_put(:okLabel, opts[:ok_label])
      |> maybe_put(:cancelLabel, opts[:cancel_label])

    ExTauri.Hook.push_command(socket, "dialog_message", payload)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
