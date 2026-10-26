defmodule ExTauri.PackagerTest do
  use ExUnit.Case, async: true

  alias ExTauri.Packager

  doctest ExTauri.Packager

  describe "ampoule_target/1" do
    test "maps the macOS and Linux triples ampoule builds for" do
      assert {:ok, "aarch64-darwin"} = Packager.ampoule_target("aarch64-apple-darwin")
      assert {:ok, "x86_64-darwin"} = Packager.ampoule_target("x86_64-apple-darwin")
      assert {:ok, "aarch64-linux"} = Packager.ampoule_target("aarch64-unknown-linux-gnu")
      assert {:ok, "x86_64-linux"} = Packager.ampoule_target("x86_64-unknown-linux-musl")
    end

    test "refuses what ampoule has no runtime for" do
      # A universal binary would need both architectures' payloads in one file,
      # and ampoule appends exactly one. iOS gets the Mac's binary instead — the
      # simulator runs it — so the iOS triples are refused here too.
      for triple <-
            ~w(x86_64-pc-windows-msvc universal-apple-darwin aarch64-apple-ios aarch64-linux-android) do
        assert {:error, message} = Packager.ampoule_target(triple)
        assert message =~ triple
      end
    end
  end
end
