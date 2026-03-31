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

    test "imports from @tauri-apps plugin packages" do
      source = Hook.js_source()
      assert source =~ "@tauri-apps/plugin-notification"
      assert source =~ "@tauri-apps/plugin-clipboard-manager"
      assert source =~ "@tauri-apps/plugin-dialog"
      assert source =~ "@tauri-apps/plugin-os"
      assert source =~ "@tauri-apps/api/core"
    end
  end
end
