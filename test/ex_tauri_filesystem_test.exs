defmodule ExTauri.FilesystemTest do
  use ExUnit.Case, async: true

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
