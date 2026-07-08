defmodule ExTauri.Hook do
  @moduledoc """
  Provides a LiveView JS hook for bridging Phoenix LiveView with Tauri APIs.

  This module generates the JavaScript hook that enables bidirectional
  communication between Elixir/LiveView and Tauri's desktop APIs
  (notifications, clipboard, dialogs, file system, etc.).

  ## Setup

  1. Add the hook to your LiveView JS app:

      ```javascript
      // assets/js/app.js
      import { TauriHook } from "../vendor/ex_tauri"

      let liveSocket = new LiveSocket("/live", Socket, {
        hooks: { TauriHook },
        // ... other options
      })
      ```

  2. Attach the hook to a DOM element in your LiveView template:

      ```heex
      <div id="tauri-bridge" phx-hook="TauriHook"></div>
      ```

  3. Use `ExTauri.Hook.push_command/3` in your LiveView to invoke Tauri APIs:

      ```elixir
      def handle_event("send_notification", _params, socket) do
        socket = ExTauri.Hook.push_command(socket, "notification", %{
          title: "Hello",
          body: "World"
        })
        {:noreply, socket}
      end
      ```

  ## How It Works

  - LiveView pushes a `"tauri_command"` event to the JS hook via `push_event/3`
  - The JS hook receives the event and calls the appropriate Tauri API
  - Results are sent back to the LiveView as `"tauri_response"` events
  - Errors are sent back as `"tauri_error"` events
  - Subscribed native events (see `ExTauri.Event`) and global shortcut presses
    arrive as `"tauri_event"` events

  The hook uses Tauri's global API (`window.__TAURI__`, enabled by
  `withGlobalTauri` in the generated `tauri.conf.json`), so no JavaScript
  package installation is required.

  ## Supported Commands

  Rather than pushing raw commands, prefer the higher-level modules — each
  command family has one. Plugins are installed with `mix ex_tauri.add`.

  | Command family    | Elixir API               | Rust plugin (via `mix ex_tauri.add`) |
  |-------------------|--------------------------|--------------------------------------|
  | `notification`    | `ExTauri.Notification`   | included by install                  |
  | `clipboard_*`     | `ExTauri.Clipboard`      | `clipboard`                          |
  | `dialog_*`        | `ExTauri.Dialog`         | `dialog`                             |
  | `os_info`         | `ExTauri.OS`             | `os`                                 |
  | `app_info`        | `ExTauri.App`            | none (core API)                      |
  | `fs_*`            | `ExTauri.Filesystem`     | `fs`                                 |
  | `shell_*`         | `ExTauri.Shell`          | included by install                  |
  | `window`          | `ExTauri.Window`         | none (core API)                      |
  | `event_*`         | `ExTauri.Event`          | none (core API)                      |
  | `shortcut_*`      | `ExTauri.GlobalShortcut` | `global-shortcut`                    |
  | `autostart_*`     | `ExTauri.Autostart`      | `autostart`                          |
  | `process_*`       | `ExTauri.App`            | `process`                            |
  | `updater_*`       | `ExTauri.Updater`        | `updater`                            |

  Custom Tauri commands registered via `#[tauri::command]` can also be invoked
  by using `"invoke"` as the command type with a `cmd` field in the payload.
  """

  @js_path Path.join(:code.priv_dir(:ex_tauri), "static/ex_tauri.js")
  @external_resource @js_path

  @doc """
  Pushes a Tauri command to the JS hook via LiveView's `push_event/3`.

  The command will be executed on the Tauri side and the result will be
  sent back as a `"tauri_response"` event that you can handle with
  `handle_event("tauri_response", payload, socket)`.

  ## Parameters

    * `socket` - The LiveView socket
    * `command` - The command type (e.g., "notification", "clipboard_write")
    * `payload` - A map of command parameters

  ## Examples

      # Send a notification
      push_command(socket, "notification", %{title: "Hello", body: "World"})

      # Read clipboard
      push_command(socket, "clipboard_read", %{})

      # Open file dialog
      push_command(socket, "dialog_open", %{
        title: "Select a file",
        filters: [%{name: "Images", extensions: ["png", "jpg"]}]
      })

      # Invoke a custom Tauri command
      push_command(socket, "invoke", %{cmd: "my_custom_command", args: %{key: "value"}})
  """
  @compile {:no_warn_undefined, Phoenix.LiveView}

  def push_command(socket, command, payload \\ %{}) do
    ref = System.unique_integer([:positive]) |> to_string()

    Phoenix.LiveView.push_event(socket, "tauri_command", %{
      ref: ref,
      command: command,
      payload: payload
    })
  end

  @doc """
  Pushes a Tauri command and tracks the `ref` in socket assigns for correlation.

  This is useful when you need to distinguish between multiple concurrent
  commands of the same type. The `ref` is stored under the given `assign_key`
  in socket assigns, so you can match it in `handle_event/3`.

  ## Examples

      # Push and track
      def handle_event("open_file_a", _params, socket) do
        socket = ExTauri.Hook.push_command_tracked(socket, "dialog_open", %{title: "File A"}, :file_a_ref)
        {:noreply, socket}
      end

      def handle_event("open_file_b", _params, socket) do
        socket = ExTauri.Hook.push_command_tracked(socket, "dialog_open", %{title: "File B"}, :file_b_ref)
        {:noreply, socket}
      end

      # Correlate the response
      def handle_event("tauri_response", %{"ref" => ref} = params, socket) do
        cond do
          ref == socket.assigns[:file_a_ref] -> {:noreply, assign(socket, :file_a, params["path"])}
          ref == socket.assigns[:file_b_ref] -> {:noreply, assign(socket, :file_b, params["path"])}
          true -> {:noreply, socket}
        end
      end
  """
  def push_command_tracked(socket, command, payload, assign_key) do
    ref = System.unique_integer([:positive]) |> to_string()

    socket
    |> Phoenix.LiveView.assign(assign_key, ref)
    |> Phoenix.LiveView.push_event("tauri_command", %{
      ref: ref,
      command: command,
      payload: payload
    })
  end

  @doc """
  Returns the JavaScript source code for the TauriHook.

  This can be used to generate the vendor file at build time or
  to inline the hook in your application.

  ## Example

      # In a mix task or build script:
      File.write!("assets/vendor/ex_tauri.js", ExTauri.Hook.js_source())
  """
  def js_source do
    File.read!(@js_path)
  end
end
