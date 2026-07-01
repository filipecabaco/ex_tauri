defmodule ExTauri.DialogTest do
  use ExUnit.Case, async: true

  # function_exported?/3 reports false for a module that hasn't been loaded yet,
  # and nothing else in the suite references this module — so load it first.
  setup_all do
    Code.ensure_loaded!(ExTauri.Dialog)
    :ok
  end

  describe "module API" do
    test "open/2 is defined" do
      assert function_exported?(ExTauri.Dialog, :open, 2)
    end

    test "save/2 is defined" do
      assert function_exported?(ExTauri.Dialog, :save, 2)
    end

    test "message/3 is defined" do
      assert function_exported?(ExTauri.Dialog, :message, 3)
    end

    test "confirm/3 is defined" do
      assert function_exported?(ExTauri.Dialog, :confirm, 3)
    end

    test "ask/3 is defined" do
      assert function_exported?(ExTauri.Dialog, :ask, 3)
    end
  end
end
