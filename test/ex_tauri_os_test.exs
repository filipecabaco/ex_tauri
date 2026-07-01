defmodule ExTauri.OSTest do
  use ExUnit.Case, async: true

  # function_exported?/3 reports false for a module that hasn't been loaded yet,
  # and nothing else in the suite references this module — so load it first.
  setup_all do
    Code.ensure_loaded!(ExTauri.OS)
    :ok
  end

  describe "module API" do
    test "info/1 is defined" do
      assert function_exported?(ExTauri.OS, :info, 1)
    end
  end
end
