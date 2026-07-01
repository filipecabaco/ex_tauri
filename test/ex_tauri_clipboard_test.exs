defmodule ExTauri.ClipboardTest do
  use ExUnit.Case, async: true

  # ExTauri.Clipboard delegates to ExTauri.Hook.push_command which requires
  # Phoenix.LiveView — we test that the module compiles and functions exist.
  # Actual integration is tested through the JS hook source tests.

  # function_exported?/3 reports false for a module that hasn't been loaded yet,
  # and nothing else in the suite references this module — so load it first.
  setup_all do
    Code.ensure_loaded!(ExTauri.Clipboard)
    :ok
  end

  describe "module API" do
    test "write/2 is defined" do
      assert function_exported?(ExTauri.Clipboard, :write, 2)
    end

    test "read/1 is defined" do
      assert function_exported?(ExTauri.Clipboard, :read, 1)
    end
  end
end
