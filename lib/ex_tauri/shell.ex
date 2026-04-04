defmodule ExTauri.Shell do
  @moduledoc """
  Execute shell commands and open URLs from your LiveView.

  Bridges to `tauri-plugin-shell` via the LiveView hook.

  ## Requirements

  - `tauri-plugin-shell` must be installed
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)
  - Shell commands must be allowed in your Tauri capabilities configuration

  ## Security Note

  Shell access is powerful and potentially dangerous. Tauri requires you to
  explicitly allowlist commands in your capabilities. Use scoped commands
  when possible rather than arbitrary shell execution.

  ## Examples

      # Open a URL in the default browser
      def handle_event("open_docs", _params, socket) do
        socket = ExTauri.Shell.open_url(socket, "https://hexdocs.pm/ex_tauri")
        {:noreply, socket}
      end

      # Execute a scoped command
      def handle_event("run_git_status", _params, socket) do
        socket = ExTauri.Shell.execute(socket, "git", ["status"])
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "shell_exec"} = params, socket) do
        {:noreply, assign(socket, :command_output, params["stdout"])}
      end
  """

  @doc """
  Opens a URL or path using the system's default application.

  This uses Tauri's `open` function from the shell plugin to open URLs
  in the default browser or files in their associated applications.

  ## Examples

      ExTauri.Shell.open_url(socket, "https://example.com")
      ExTauri.Shell.open_url(socket, "/path/to/document.pdf")
  """
  def open_url(socket, url) when is_binary(url) do
    uri = URI.parse(url)

    unless uri.scheme in ["http", "https", "mailto"] do
      raise ArgumentError,
            "open_url only allows http, https, and mailto schemes, got: #{inspect(uri.scheme)}"
    end

    ExTauri.Hook.push_command(socket, "shell_open", %{url: url})
  end

  @doc """
  Executes a scoped shell command.

  Commands must be allowlisted in your Tauri capabilities configuration.
  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "shell_exec", "stdout" => "...", "stderr" => "...", "code" => 0}`.

  ## Examples

      ExTauri.Shell.execute(socket, "git", ["status"])
      ExTauri.Shell.execute(socket, "node", ["--version"])
  """
  def execute(socket, program, args \\ []) do
    ExTauri.Hook.push_command(socket, "shell_exec", %{program: program, args: args})
  end
end
