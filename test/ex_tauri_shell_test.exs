defmodule ExTauri.ShellTest do
  use ExUnit.Case, async: true

  # function_exported?/3 reports false for a module that hasn't been loaded yet,
  # and nothing else in the suite references this module — so load it first.
  setup_all do
    Code.ensure_loaded!(ExTauri.Shell)
    :ok
  end

  describe "module API" do
    test "open_url/2 is defined" do
      assert function_exported?(ExTauri.Shell, :open_url, 2)
    end

    test "execute/3 is defined" do
      assert function_exported?(ExTauri.Shell, :execute, 3)
    end
  end
end
