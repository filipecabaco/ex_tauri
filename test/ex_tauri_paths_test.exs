defmodule ExTauri.PathsTest do
  use ExUnit.Case, async: false

  alias ExTauri.Paths

  setup do
    original_app_name = Application.get_env(:ex_tauri, :app_name)

    on_exit(fn ->
      if original_app_name do
        Application.put_env(:ex_tauri, :app_name, original_app_name)
      else
        Application.delete_env(:ex_tauri, :app_name)
      end
    end)

    :ok
  end

  describe "app_identifier/0" do
    test "normalizes app name to filesystem-safe identifier" do
      Application.put_env(:ex_tauri, :app_name, "My Desktop App")
      assert Paths.app_identifier() == "my_desktop_app"
    end

    test "handles simple names" do
      Application.put_env(:ex_tauri, :app_name, "myapp")
      assert Paths.app_identifier() == "myapp"
    end

    test "defaults to ex_tauri_app when not configured" do
      Application.delete_env(:ex_tauri, :app_name)
      assert Paths.app_identifier() == "ex_tauri_app"
    end
  end

  describe "data_dir/0" do
    test "returns a path containing the app identifier" do
      Application.put_env(:ex_tauri, :app_name, "Test App")
      path = Paths.data_dir()

      assert is_binary(path)
      assert String.contains?(path, "test_app")
      assert File.dir?(path)
    end

    test "creates the directory if it doesn't exist" do
      Application.put_env(:ex_tauri, :app_name, "paths_test_#{System.unique_integer([:positive])}")
      path = Paths.data_dir()

      assert File.dir?(path)
      File.rm_rf!(path)
    end

    test "returns platform-appropriate path on Linux" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.data_dir()
        assert String.contains?(path, ".local/share/test_app")
      end
    end

    test "returns platform-appropriate path on macOS" do
      if :os.type() == {:unix, :darwin} do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.data_dir()
        assert String.contains?(path, "Library/Application Support/test_app")
      end
    end
  end

  describe "config_dir/0" do
    test "returns a path containing the app identifier" do
      Application.put_env(:ex_tauri, :app_name, "Test App")
      path = Paths.config_dir()

      assert is_binary(path)
      assert String.contains?(path, "test_app")
      assert File.dir?(path)
    end

    test "returns .config on Linux" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.config_dir()
        assert String.contains?(path, ".config/test_app")
      end
    end
  end

  describe "cache_dir/0" do
    test "returns a path containing the app identifier" do
      Application.put_env(:ex_tauri, :app_name, "Test App")
      path = Paths.cache_dir()

      assert is_binary(path)
      assert String.contains?(path, "test_app")
      assert File.dir?(path)
    end

    test "returns .cache on Linux" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.cache_dir()
        assert String.contains?(path, ".cache/test_app")
      end
    end

    test "returns Library/Caches on macOS" do
      if :os.type() == {:unix, :darwin} do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.cache_dir()
        assert String.contains?(path, "Library/Caches/test_app")
      end
    end
  end

  describe "log_dir/0" do
    test "returns a path containing the app identifier" do
      Application.put_env(:ex_tauri, :app_name, "Test App")
      path = Paths.log_dir()

      assert is_binary(path)
      assert String.contains?(path, "test_app")
      assert File.dir?(path)
    end

    test "returns .local/state path with log suffix on Linux" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.log_dir()
        assert String.contains?(path, "test_app")
        assert String.ends_with?(path, "/log")
      end
    end

    test "returns Library/Logs on macOS" do
      if :os.type() == {:unix, :darwin} do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        path = Paths.log_dir()
        assert String.contains?(path, "Library/Logs/test_app")
      end
    end
  end

  describe "XDG overrides on Linux" do
    test "respects XDG_DATA_HOME" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        custom_dir = Path.join(System.tmp_dir!(), "xdg_test_data_#{System.unique_integer([:positive])}")
        System.put_env("XDG_DATA_HOME", custom_dir)

        path = Paths.data_dir()
        assert String.starts_with?(path, custom_dir)
        assert String.contains?(path, "test_app")

        System.delete_env("XDG_DATA_HOME")
        File.rm_rf!(custom_dir)
      end
    end

    test "respects XDG_CONFIG_HOME" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        custom_dir = Path.join(System.tmp_dir!(), "xdg_test_config_#{System.unique_integer([:positive])}")
        System.put_env("XDG_CONFIG_HOME", custom_dir)

        path = Paths.config_dir()
        assert String.starts_with?(path, custom_dir)

        System.delete_env("XDG_CONFIG_HOME")
        File.rm_rf!(custom_dir)
      end
    end

    test "respects XDG_CACHE_HOME" do
      if match?({:unix, linux} when linux != :darwin, :os.type()) do
        Application.put_env(:ex_tauri, :app_name, "Test App")
        custom_dir = Path.join(System.tmp_dir!(), "xdg_test_cache_#{System.unique_integer([:positive])}")
        System.put_env("XDG_CACHE_HOME", custom_dir)

        path = Paths.cache_dir()
        assert String.starts_with?(path, custom_dir)

        System.delete_env("XDG_CACHE_HOME")
        File.rm_rf!(custom_dir)
      end
    end
  end

  describe "sanitize_name/1" do
    test "strips path traversal sequences" do
      assert Paths.sanitize_name("../../etc/evil") == "etcevil"
      assert Paths.sanitize_name("app/../secret") == "appsecret"
    end

    test "strips path separators" do
      assert Paths.sanitize_name("path/to/app") == "pathtoapp"
      assert Paths.sanitize_name("path\\to\\app") == "pathtoapp"
    end

    test "replaces spaces with underscores" do
      assert Paths.sanitize_name("My App") == "my_app"
    end

    test "removes special characters" do
      assert Paths.sanitize_name("app@name!#$%") == "appname"
    end

    test "lowercases the result" do
      assert Paths.sanitize_name("MyApp") == "myapp"
    end

    test "allows hyphens and underscores" do
      assert Paths.sanitize_name("my-app_name") == "my-app_name"
    end

    test "falls back to default for empty result" do
      assert Paths.sanitize_name("../..") == "ex_tauri_app"
      assert Paths.sanitize_name("///") == "ex_tauri_app"
    end
  end
end
