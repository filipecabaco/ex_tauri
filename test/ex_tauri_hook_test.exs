defmodule ExTauri.HookTest do
  use ExUnit.Case, async: true

  alias ExTauri.Hook

  describe "js_source/0" do
    test "returns JavaScript source code" do
      source = Hook.js_source()
      assert is_binary(source)
      assert String.length(source) > 0
    end

    test "exports TauriHook with mounted callback" do
      source = Hook.js_source()
      assert source =~ "export const TauriHook"
      assert source =~ "mounted()"
    end

    test "includes command allowlist for security" do
      source = Hook.js_source()
      assert source =~ "ALLOWED_COMMANDS"
      assert source =~ "Blocked unknown Tauri command"
    end

    test "handles tauri_command events" do
      source = Hook.js_source()
      assert source =~ ~s(this.handleEvent("tauri_command")
    end

    test "supports notification command" do
      source = Hook.js_source()
      assert source =~ ~s(case "notification")
      assert source =~ "sendNotification"
      assert source =~ "isPermissionGranted"
    end

    test "supports clipboard commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "clipboard_write")
      assert source =~ ~s(case "clipboard_read")
      assert source =~ "writeText"
      assert source =~ "readText"
    end

    test "supports dialog commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "dialog_open")
      assert source =~ ~s(case "dialog_save")
      assert source =~ ~s(case "dialog_message")
    end

    test "supports os_info command" do
      source = Hook.js_source()
      assert source =~ ~s(case "os_info")
      assert source =~ "platform"
      assert source =~ "arch"
    end

    test "supports custom invoke command" do
      source = Hook.js_source()
      assert source =~ ~s(case "invoke")
      assert source =~ "payload.cmd"
    end

    test "sends tauri_response on success" do
      source = Hook.js_source()
      assert source =~ ~s(this.pushEvent("tauri_response")
    end

    test "sends tauri_error on failure" do
      source = Hook.js_source()
      assert source =~ ~s(this.pushEvent("tauri_error")
    end

    test "checks for Tauri environment" do
      source = Hook.js_source()
      assert source =~ "window.__TAURI__"
      assert source =~ "isTauri()"
    end

    test "supports filesystem commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "fs_read")
      assert source =~ ~s(case "fs_write")
      assert source =~ ~s(case "fs_exists")
      assert source =~ ~s(case "fs_readdir")
      assert source =~ ~s(case "fs_remove")
      assert source =~ ~s(case "fs_mkdir")
      assert source =~ "readTextFile"
      assert source =~ "writeTextFile"
    end

    test "supports shell commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "shell_open")
      assert source =~ ~s(case "shell_exec")
      assert source =~ "Command.create"
    end

    test "uses the global Tauri API instead of npm packages" do
      source = Hook.js_source()

      # Namespaces resolved off window.__TAURI__ via tauriApi(...)
      for namespace <- ~w(notification clipboardManager dialog os fs shell core
                          window webviewWindow app event globalShortcut autostart process
                          updater dpi) do
        assert source =~ ~s(tauriApi("#{namespace}")),
               "expected tauriApi(\"#{namespace}\") in hook source"
      end

      # No @tauri-apps imports remain — a stock Phoenix esbuild setup has no
      # node_modules, so bundling would fail if any were present.
      refute source =~ "@tauri-apps"
      refute source =~ "import("
    end

    test "supports runtime window management" do
      source = Hook.js_source()
      assert source =~ ~s(case "window")
      assert source =~ "getCurrentWindow"

      for action <- ~w(minimize maximize unmaximize toggle_maximize set_fullscreen set_title
                       set_size center set_focus hide show set_always_on_top set_resizable
                       start_dragging info) do
        assert source =~ ~s(case "#{action}"), "expected window action: #{action}"
      end
    end

    test "supports multi-window commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "window_open")
      assert source =~ ~s(case "window_close")
      assert source =~ "WebviewWindow"
      assert source =~ "getByLabel"
    end

    test "supports app info command" do
      source = Hook.js_source()
      assert source =~ ~s(case "app_info")
      assert source =~ "getVersion"
      assert source =~ "getTauriVersion"
    end

    test "supports event subscription commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "event_listen")
      assert source =~ ~s(case "event_unlisten")
      assert source =~ ~s(case "event_emit")
    end

    test "forwards subscribed events and shortcuts as tauri_event" do
      source = Hook.js_source()
      assert source =~ ~s(pushEvent("tauri_event")
      assert source =~ ~s("global_shortcut")
    end

    test "supports global shortcut commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "shortcut_register")
      assert source =~ ~s(case "shortcut_unregister")
      assert source =~ ~s(case "shortcut_is_registered")
    end

    test "supports autostart commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "autostart_enable")
      assert source =~ ~s(case "autostart_disable")
      assert source =~ ~s(case "autostart_status")
    end

    test "supports process commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "process_exit")
      assert source =~ ~s(case "process_relaunch")
    end

    test "supports updater commands" do
      source = Hook.js_source()
      assert source =~ ~s(case "updater_check")
      assert source =~ ~s(case "updater_install")
      assert source =~ "downloadAndInstall"
    end

    test "cleans up event listeners when the hook is destroyed" do
      source = Hook.js_source()
      assert source =~ "destroyed()"
      assert source =~ "_eventUnlisteners"
    end
  end
end
