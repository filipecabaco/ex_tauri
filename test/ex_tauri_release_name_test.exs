defmodule ExTauri.ReleaseNameTest do
  # Reads and writes :ex_tauri application env.
  use ExUnit.Case, async: false

  alias ExTauri.Install.Helpers

  setup do
    on_exit(fn -> Application.delete_env(:ex_tauri, :release_name) end)
    :ok
  end

  describe "ExTauri.release_name/0" do
    test "defaults to what every app installed before this was given" do
      Application.delete_env(:ex_tauri, :release_name)

      assert "desktop" = ExTauri.release_name()
      assert :desktop = ExTauri.release_name_atom()
    end

    test "follows :release_name, as a string or an atom" do
      Application.put_env(:ex_tauri, :release_name, "my_app_desktop")
      assert "my_app_desktop" = ExTauri.release_name()
      assert :my_app_desktop = ExTauri.release_name_atom()

      Application.put_env(:ex_tauri, :release_name, :other_desktop)
      assert "other_desktop" = ExTauri.release_name()
    end
  end

  describe "default_release_name/1" do
    test "derives the name a fresh install is given" do
      assert "my_app_desktop" = ExTauri.default_release_name(:my_app)
    end

    test "keeps the suffix even when it reads badly, because Tauri requires it" do
      # `francis_desktop_desktop` is silly, and dropping the suffix is worse:
      # Tauri refuses a sidecar named the same as the Cargo package, which is the
      # app name. Returning "francis_desktop" here failed the Francis CLI flow.
      assert "francis_desktop_desktop" = ExTauri.default_release_name(:francis_desktop)
    end

    test "never returns the application name itself" do
      # The property the test above is a case of: sidecar name != package name.
      for app <- [:my_app, :francis_desktop, :desktop, :a] do
        refute ExTauri.default_release_name(app) == to_string(app)
      end
    end
  end

  describe "generated artifacts name the same binary" do
    # Burrito names the sidecar binary, and its unpack directory, after the
    # release. Three generated files have to agree with mix.exs about that name
    # or the window comes up with no backend behind it, so they are checked
    # together rather than one at a time.
    test "main.rs spawns the release's sidecar" do
      main_rs = Helpers.main_src("localhost", "4000", "app", "App", "http", "my_app_desktop")

      assert main_rs =~ ~s{sidecar("my_app_desktop")}
      refute main_rs =~ ~s{sidecar("desktop")}
    end

    test "the shell capability allows the release's sidecar" do
      capabilities = Helpers.capabilities_json("my_app_desktop")

      assert %{"permissions" => permissions} = Jason.decode!(capabilities)

      allowed =
        Enum.find_value(permissions, fn
          %{"identifier" => "shell:allow-execute", "allow" => allow} -> allow
          _other -> nil
        end)

      assert [%{"name" => "my_app_desktop", "sidecar" => true}] = allowed
    end

    test "both still default to desktop, so an existing install regenerates unchanged" do
      assert Helpers.main_src("localhost", "4000", "app") =~ ~s{sidecar("desktop")}
      assert Helpers.capabilities_json() =~ ~s{"name": "desktop"}
    end
  end
end
