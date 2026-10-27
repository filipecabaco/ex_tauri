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

  describe "under ampoule" do
    @describetag :tmp_dir

    setup %{tmp_dir: tmp_dir} do
      Application.put_env(:ex_tauri, :app_name, "Home Test")
      System.put_env("EX_TAURI_HOME", tmp_dir)

      # On Linux an XDG variable rightly wins over the home, and CI runners set
      # them; these tests are about the home, so clear them for the duration.
      xdg = ~w(XDG_DATA_HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DOCUMENTS_DIR)
      saved = Map.new(xdg, &{&1, System.get_env(&1)})
      Enum.each(xdg, &System.delete_env/1)

      on_exit(fn ->
        System.delete_env("EX_TAURI_HOME")
        System.delete_env("EX_TAURI_HOST_OS")

        for {key, value} <- saved, value != nil, do: System.put_env(key, value)
      end)

      :ok
    end

    test "EX_TAURI_HOME replaces the home, which ampoule makes a deleted-on-exit /tmp",
         %{tmp_dir: tmp_dir} do
      for dir <- [Paths.data_dir(), Paths.config_dir(), Paths.cache_dir(), Paths.log_dir()] do
        assert String.starts_with?(dir, tmp_dir <> "/")
        assert dir =~ "home_test"
      end
    end

    test "EX_TAURI_HOST_OS names the OS, since the guest reports Linux everywhere",
         %{tmp_dir: tmp_dir} do
      # Otherwise a macOS app would keep its data in ~/.local/share and lose it
      # when it switched packagers.
      System.put_env("EX_TAURI_HOST_OS", "macos")

      assert Paths.data_dir() ==
               Path.join([tmp_dir, "Library", "Application Support", "home_test"])

      System.put_env("EX_TAURI_HOST_OS", "linux")
      System.delete_env("XDG_DATA_HOME")
      assert Paths.data_dir() == Path.join([tmp_dir, ".local", "share", "home_test"])
    end

    test "iOS keeps the macOS layout inside the app's container", %{tmp_dir: tmp_dir} do
      System.put_env("EX_TAURI_HOST_OS", "ios")

      assert Paths.data_dir() ==
               Path.join([tmp_dir, "Library", "Application Support", "home_test"])

      assert Paths.cache_dir() == Path.join([tmp_dir, "Library", "Caches", "home_test"])
      # The folder the Files app shows for the app.
      assert Paths.documents_dir() == Path.join(tmp_dir, "Documents")
      assert File.dir?(Paths.documents_dir())
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
      Application.put_env(
        :ex_tauri,
        :app_name,
        "paths_test_#{System.unique_integer([:positive])}"
      )

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

        custom_dir =
          Path.join(System.tmp_dir!(), "xdg_test_data_#{System.unique_integer([:positive])}")

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

        custom_dir =
          Path.join(System.tmp_dir!(), "xdg_test_config_#{System.unique_integer([:positive])}")

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

        custom_dir =
          Path.join(System.tmp_dir!(), "xdg_test_cache_#{System.unique_integer([:positive])}")

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
