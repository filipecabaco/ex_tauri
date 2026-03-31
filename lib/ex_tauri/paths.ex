defmodule ExTauri.Paths do
  @moduledoc """
  Provides platform-appropriate directory paths for desktop applications.

  Desktop apps need to store data, configuration, cache, and logs in
  OS-standard locations. This module resolves the correct paths based
  on the current platform and the configured `:app_name`.

  ## Paths by Platform

  | Function      | macOS                                    | Linux                              |
  |---------------|------------------------------------------|------------------------------------|
  | `data_dir/0`  | `~/Library/Application Support/<app>`    | `~/.local/share/<app>`             |
  | `config_dir/0`| `~/Library/Application Support/<app>`    | `~/.config/<app>`                  |
  | `cache_dir/0` | `~/Library/Caches/<app>`                 | `~/.cache/<app>`                   |
  | `log_dir/0`   | `~/Library/Logs/<app>`                   | `~/.local/state/<app>/log`         |

  All directories are created automatically if they don't exist.

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
  Returns the normalized app name used for directory names.

  Converts the configured `:app_name` to a filesystem-safe identifier.
  """
  def app_identifier do
    Application.get_env(:ex_tauri, :app_name, "ex_tauri_app")
    |> String.replace(" ", "_")
    |> String.downcase()
  end

  # Platform-specific path resolution

  defp data_dir_path do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Application Support", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_DATA_HOME", ".local/share")
    end
  end

  defp config_dir_path do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Application Support", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_CONFIG_HOME", ".config")
    end
  end

  defp cache_dir_path do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Caches", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_CACHE_HOME", ".cache")
    end
  end

  defp log_dir_path do
    case :os.type() do
      {:unix, :darwin} ->
        Path.join([System.user_home!(), "Library", "Logs", app_identifier()])

      {:unix, _} ->
        xdg_or_default("XDG_STATE_HOME", ".local/state")
        |> Path.join("log")
    end
  end

  defp xdg_or_default(env_var, default_suffix) do
    base =
      System.get_env(env_var) ||
        Path.join(System.user_home!(), default_suffix)

    Path.join(base, app_identifier())
  end

  defp ensure_dir(path) do
    File.mkdir_p!(path)
    path
  end
end
