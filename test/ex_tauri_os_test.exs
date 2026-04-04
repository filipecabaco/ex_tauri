defmodule ExTauri.OSTest do
  use ExUnit.Case, async: true

  describe "module API" do
    test "info/1 is defined" do
      assert function_exported?(ExTauri.OS, :info, 1)
    end
  end
end
