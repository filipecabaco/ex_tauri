defmodule ExTauriTest do
  use ExUnit.Case, async: true
  doctest ExTauri

  describe "latest_version/0" do
    test "returns the latest Tauri version" do
      assert ExTauri.latest_version() == "2.5.1"
    end
  end

  describe "installation_path/0" do
    test "returns a valid path" do
      path = ExTauri.installation_path()
      assert is_binary(path)
      assert String.contains?(path, "_tauri")
    end
  end
end
