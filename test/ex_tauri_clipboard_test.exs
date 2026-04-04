defmodule ExTauri.ClipboardTest do
  use ExUnit.Case, async: true

  # ExTauri.Clipboard delegates to ExTauri.Hook.push_command which requires
  # Phoenix.LiveView — we test that the module compiles and functions exist.
  # Actual integration is tested through the JS hook source tests.

  describe "module API" do
    test "write/2 is defined" do
      assert function_exported?(ExTauri.Clipboard, :write, 2)
    end

    test "read/1 is defined" do
      assert function_exported?(ExTauri.Clipboard, :read, 1)
    end
  end
end
