defmodule ExTauri.FilesystemTest do
  use ExUnit.Case, async: true

  # function_exported?/3 reports false for a module that hasn't been loaded yet,
  # and nothing else in the suite references this module — so load it first.
  setup_all do
    Code.ensure_loaded!(ExTauri.Filesystem)
    :ok
  end

  describe "module API" do
    test "read/3 is defined" do
      assert function_exported?(ExTauri.Filesystem, :read, 3)
    end

    test "write/4 is defined" do
      assert function_exported?(ExTauri.Filesystem, :write, 4)
    end

    test "exists?/3 is defined" do
      assert function_exported?(ExTauri.Filesystem, :exists?, 3)
    end

    test "readdir/3 is defined" do
      assert function_exported?(ExTauri.Filesystem, :readdir, 3)
    end

    test "remove/3 is defined" do
      assert function_exported?(ExTauri.Filesystem, :remove, 3)
    end

    test "mkdir/3 is defined" do
      assert function_exported?(ExTauri.Filesystem, :mkdir, 3)
    end
  end
end
