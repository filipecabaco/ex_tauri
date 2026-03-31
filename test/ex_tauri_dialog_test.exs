defmodule ExTauri.DialogTest do
  use ExUnit.Case, async: true

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
