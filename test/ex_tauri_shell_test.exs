defmodule ExTauri.ShellTest do
  use ExUnit.Case, async: true

  describe "module API" do
    test "open_url/2 is defined" do
      assert function_exported?(ExTauri.Shell, :open_url, 2)
    end

    test "execute/3 is defined" do
      assert function_exported?(ExTauri.Shell, :execute, 3)
    end
  end
end
