defmodule ExTauri.Paths do
  @moduledoc """
  Provides platform-appropriate directory paths for desktop applications.

  Desktop apps need to store data, configuration, cache, and logs in
  OS-standard locations. This module resolves the correct paths based
  on the current platform and the configured `:app_name`.

  ## Paths by Platform

  | Function      | macOS                                    | Linux                              | Windows                            |
  |---------------|------------------------------------------|------------------------------------|------------------------------------|
  | `data_dir/0`  | `~/Library/Application Support/<app>`    | `~/.local/share/<app>`             | `%APPDATA%/<app>`                  |
  | `config_dir/0`| `~/Library/Application Support/<app>`    | `~/.config/<app>`                  | `%APPDATA%/<app>`                  |
  | `cache_dir/0` | `~/Library/Caches/<app>`                 | `~/.cache/<app>`                   | `%LOCALAPPDATA%/<app>/cache`       |
  | `log_dir/0`   | `~/Library/Logs/<app>`                   | `~/.local/state/<app>/log`         | `%LOCALAPPDATA%/<app>/log`         |
  | `documents_dir/0` | `~/Documents`                        | `$XDG_DOCUMENTS_DIR` or `~/Documents` | `%USERPROFILE%/Documents`       |

  iOS uses the macOS layout inside the app's sandbox container, where
  `documents_dir/0` is the folder the Files app shows for the app.

  All directories are created automatically if they don't exist.

  ## Under ampoule

  An ampoule sidecar (see `ExTauri.Packager`) sees its own home as a private
  temporary directory that is deleted when it exits, and reports itself as
  Linux on every host. The generated shells therefore name both: `~` is
  `EX_TAURI_HOME` when set, otherwise `System.user_home!/0`, and the platform is
  `EX_TAURI_HOST_OS` (`macos`, `ios` or `linux`) when set, otherwise
  `:os.type/0`. Without them, data written here would vanish with the sidecar,
  or a macOS app would keep it under `~/.local/share`.

  ## Configuration

      config :ex_tauri, :app_name, "My Desktop App"

  The app name is normalized to a filesystem-safe identifier
  (lowercased, spaces replaced with underscores).

  ## Examples

      iex> ExTauri.Paths.data_dir()
      "/home/user/.local/share/my_desktop_app"

      iex> ExTauri.Paths.config_dir()
      "/home/user/.config/my_desktop_app"
  """

  @doc """
  Returns the platform-appropriate data directory for the application.

  Use this for persistent application data like databases, user files, etc.
  """
  def data_dir do
    ensure_dir(data_dir_path())
  end

  @doc """
  Returns the platform-appropriate configuration directory.

  Use this for user configuration and preferences.
  """
  def config_dir do
    ensure_dir(config_dir_path())
  end

  @doc """
  Returns the platform-appropriate cache directory.

  Use this for temporary data that can be regenerated. The OS may
  clear this directory to free disk space.
  """
  def cache_dir do
    ensure_dir(cache_dir_path())
  end

  @doc """
  Returns the platform-appropriate log directory.

  Use this for application log files.
  """
  def log_dir do
    ensure_dir(log_dir_path())
  end

  @doc """
  Returns the user's documents directory.

  Not specific to the app: this is where people keep files they open and save
  themselves. On iOS it is the app's own Documents folder, the one the Files
  app shows.
  """
  def documents_dir do
    ensure_dir(documents_dir_path())
  end

  @doc """
  Returns the normalized app name used for directory names.

  Converts the configured `:app_name` to a filesystem-safe identifier.
  """
  def app_identifier do
    Application.get_env(:ex_tauri, :app_name, "ex_tauri_app")
    |> sanitize_name()
  end

  @doc """
  Sanitizes a name for safe use in filesystem paths.

  Strips path separators and traversal sequences, replaces spaces with
  underscores, removes any characters that aren't alphanumeric, underscores,
  or hyphens, and lowercases the result.
  """
  def sanitize_name(name) when is_binary(name) do
    name
    |> String.replace(~r/[\/\\]/, "")
    |> String.replace("..", "")
    |> String.replace(" ", "_")
    |> String.replace(~r/[^a-zA-Z0-9_\-]/, "")
    |> String.downcase()
    |> case do
      "" -> "ex_tauri_app"
      sanitized -> sanitized
    end
  end

  # Platform-specific path resolution

  defp data_dir_path do
    case os_type() do
      {:unix, :darwin} ->
        Path.join([home(), "Library", "Application Support", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_DATA_HOME", ".local/share")

      {:win32, _} ->
        appdata = System.get_env("APPDATA") || Path.join(home(), "AppData/Roaming")
        Path.join(appdata, app_identifier())
    end
  end

  defp config_dir_path do
    case os_type() do
      {:unix, :darwin} ->
        Path.join([home(), "Library", "Application Support", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_CONFIG_HOME", ".config")

      {:win32, _} ->
        appdata = System.get_env("APPDATA") || Path.join(home(), "AppData/Roaming")
        Path.join(appdata, app_identifier())
    end
  end

  defp cache_dir_path do
    case os_type() do
      {:unix, :darwin} ->
        Path.join([home(), "Library", "Caches", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_CACHE_HOME", ".cache")

      {:win32, _} ->
        local = System.get_env("LOCALAPPDATA") || Path.join(home(), "AppData/Local")
        Path.join([local, app_identifier(), "cache"])
    end
  end

  defp log_dir_path do
    case os_type() do
      {:unix, :darwin} ->
        Path.join([home(), "Library", "Logs", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_STATE_HOME", ".local/state")
        |> Path.join("log")

      {:win32, _} ->
        local = System.get_env("LOCALAPPDATA") || Path.join(home(), "AppData/Local")
        Path.join([local, app_identifier(), "log"])
    end
  end

  defp documents_dir_path do
    case os_type() do
      {:unix, :linux} -> System.get_env("XDG_DOCUMENTS_DIR") || Path.join(home(), "Documents")
      _ -> Path.join(home(), "Documents")
    end
  end

  defp home, do: System.get_env("EX_TAURI_HOME") || System.user_home!()

  # iOS keeps the macOS layout inside its sandbox container.
  defp os_type do
    case System.get_env("EX_TAURI_HOST_OS") do
      os when os in ["macos", "ios"] -> {:unix, :darwin}
      "linux" -> {:unix, :linux}
      _ -> :os.type()
    end
  end

  defp xdg_or_default(env_var, default_suffix) do
    base =
      System.get_env(env_var) ||
        Path.join(home(), default_suffix)

    Path.join(base, app_identifier())
  end

  defp ensure_dir(path) do
    # Cache created directories in the process dictionary to avoid
    # repeated mkdir_p! syscalls on every access
    cache_key = {:ex_tauri_dir_created, path}

    unless Process.get(cache_key) do
      File.mkdir_p!(path)
      Process.put(cache_key, true)
    end

    path
  end
end
