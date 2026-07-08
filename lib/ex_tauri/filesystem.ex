defmodule ExTauri.Filesystem do
  @moduledoc """
  Read and write files on the desktop filesystem from your LiveView.

  Bridges to `tauri-plugin-fs` via the LiveView hook. This allows your
  LiveView to read/write files outside the web sandbox.

  ## Requirements

  - `tauri-plugin-fs` must be installed (see Plugin Setup below)
  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)
  - Appropriate filesystem permissions must be configured in capabilities

  ## Plugin Setup

      mix ex_tauri.add fs

  This adds the Cargo dependency, registers the plugin in `main.rs`, and adds
  the `fs:default` capability. See `Mix.Tasks.ExTauri.Add` for details.

  For broader access, add scoped permissions to
  `src-tauri/capabilities/default.json`:

      {
        "identifier": "fs:allow-read-text-file",
        "allow": [{"path": "$APPDATA/**"}]
      }

  ## Examples

      # Read a file
      def handle_event("read_file", %{"path" => path}, socket) do
        socket = ExTauri.Filesystem.read(socket, path)
        {:noreply, socket}
      end

      # Handle the response
      def handle_event("tauri_response", %{"command" => "fs_read", "contents" => contents}, socket) do
        {:noreply, assign(socket, :file_contents, contents)}
      end
  """

  @doc """
  Reads a file from the filesystem.

  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "fs_read", "contents" => "..."}`.

  ## Options

    * `:base_dir` - Base directory for relative paths (e.g., "AppData", "Home", "Desktop")

  ## Examples

      ExTauri.Filesystem.read(socket, "/path/to/file.txt")
      ExTauri.Filesystem.read(socket, "config.json", base_dir: "AppData")
  """
  def read(socket, path, opts \\ []) do
    payload =
      %{path: path}
      |> maybe_put(:baseDir, opts[:base_dir])

    ExTauri.Hook.push_command(socket, "fs_read", payload)
  end

  @doc """
  Writes content to a file on the filesystem.

  ## Options

    * `:base_dir` - Base directory for relative paths
    * `:append` - Append to file instead of overwriting (default: false)

  ## Examples

      ExTauri.Filesystem.write(socket, "/path/to/file.txt", "Hello, world!")
      ExTauri.Filesystem.write(socket, "log.txt", "entry\\n", base_dir: "AppData", append: true)
  """
  def write(socket, path, contents, opts \\ []) do
    payload =
      %{path: path, contents: contents}
      |> maybe_put(:baseDir, opts[:base_dir])
      |> maybe_put(:append, opts[:append])

    ExTauri.Hook.push_command(socket, "fs_write", payload)
  end

  @doc """
  Checks if a file or directory exists.

  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "fs_exists", "exists" => true | false}`.

  ## Options

    * `:base_dir` - Base directory for relative paths

  ## Examples

      ExTauri.Filesystem.exists?(socket, "/path/to/file.txt")
  """
  def exists?(socket, path, opts \\ []) do
    payload =
      %{path: path}
      |> maybe_put(:baseDir, opts[:base_dir])

    ExTauri.Hook.push_command(socket, "fs_exists", payload)
  end

  @doc """
  Lists entries in a directory.

  The result will be sent back as a `"tauri_response"` event with
  `%{"command" => "fs_readdir", "entries" => [...]}`.

  ## Options

    * `:base_dir` - Base directory for relative paths

  ## Examples

      ExTauri.Filesystem.readdir(socket, "/path/to/directory")
  """
  def readdir(socket, path, opts \\ []) do
    payload =
      %{path: path}
      |> maybe_put(:baseDir, opts[:base_dir])

    ExTauri.Hook.push_command(socket, "fs_readdir", payload)
  end

  @doc """
  Removes a file.

  ## Options

    * `:base_dir` - Base directory for relative paths

  ## Examples

      ExTauri.Filesystem.remove(socket, "/path/to/file.txt")
  """
  def remove(socket, path, opts \\ []) do
    payload =
      %{path: path}
      |> maybe_put(:baseDir, opts[:base_dir])

    ExTauri.Hook.push_command(socket, "fs_remove", payload)
  end

  @doc """
  Creates a directory (and parent directories if needed).

  ## Options

    * `:base_dir` - Base directory for relative paths
    * `:recursive` - Create parent directories (default: true)

  ## Examples

      ExTauri.Filesystem.mkdir(socket, "/path/to/new/directory")
  """
  def mkdir(socket, path, opts \\ []) do
    payload =
      %{path: path, recursive: Keyword.get(opts, :recursive, true)}
      |> maybe_put(:baseDir, opts[:base_dir])

    ExTauri.Hook.push_command(socket, "fs_mkdir", payload)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
