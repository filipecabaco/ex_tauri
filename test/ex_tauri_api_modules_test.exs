defmodule ExTauri.ApiModulesTest do
  use ExUnit.Case, async: true

  # function_exported?/3 reports false for modules that haven't been loaded yet,
  # and nothing else in the suite references these modules — so load them first.
  setup_all do
    for mod <- [
          ExTauri.Window,
          ExTauri.App,
          ExTauri.Event,
          ExTauri.GlobalShortcut,
          ExTauri.Autostart,
          ExTauri.Updater
        ] do
      Code.ensure_loaded!(mod)
    end

    :ok
  end

  describe "ExTauri.Window API" do
    test "window management functions are defined" do
      for {fun, arity} <- [
            minimize: 1,
            maximize: 1,
            unmaximize: 1,
            toggle_maximize: 1,
            set_fullscreen: 2,
            set_title: 2,
            set_size: 3,
            center: 1,
            focus: 1,
            hide: 1,
            show: 1,
            set_always_on_top: 2,
            set_resizable: 2,
            start_dragging: 1,
            info: 1
          ] do
        assert function_exported?(ExTauri.Window, fun, arity),
               "expected ExTauri.Window.#{fun}/#{arity}"
      end
    end
  end

  describe "ExTauri.App API" do
    test "app functions are defined" do
      assert function_exported?(ExTauri.App, :info, 1)
      assert function_exported?(ExTauri.App, :exit, 1)
      assert function_exported?(ExTauri.App, :exit, 2)
      assert function_exported?(ExTauri.App, :relaunch, 1)
    end
  end

  describe "ExTauri.Event API" do
    test "event functions are defined" do
      assert function_exported?(ExTauri.Event, :subscribe, 2)
      assert function_exported?(ExTauri.Event, :unsubscribe, 2)
      assert function_exported?(ExTauri.Event, :emit, 2)
      assert function_exported?(ExTauri.Event, :emit, 3)
    end
  end

  describe "ExTauri.GlobalShortcut API" do
    test "shortcut functions are defined" do
      assert function_exported?(ExTauri.GlobalShortcut, :register, 2)
      assert function_exported?(ExTauri.GlobalShortcut, :unregister, 2)
      assert function_exported?(ExTauri.GlobalShortcut, :registered?, 2)
    end
  end

  describe "ExTauri.Autostart API" do
    test "autostart functions are defined" do
      assert function_exported?(ExTauri.Autostart, :enable, 1)
      assert function_exported?(ExTauri.Autostart, :disable, 1)
      assert function_exported?(ExTauri.Autostart, :status, 1)
    end
  end

  describe "ExTauri.Updater runtime API" do
    test "runtime update functions are defined" do
      assert function_exported?(ExTauri.Updater, :check, 1)
      assert function_exported?(ExTauri.Updater, :install, 1)
    end

    test "config helpers remain available" do
      assert function_exported?(ExTauri.Updater, :config, 0)
      assert function_exported?(ExTauri.Updater, :enabled?, 0)
      assert function_exported?(ExTauri.Updater, :tauri_config, 0)
    end
  end
end
