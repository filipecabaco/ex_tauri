defmodule ExTauri.MixTasksTest do
  use ExUnit.Case, async: true

  describe "Mix.Tasks.ExTauri.Build.build_tauri_args/2" do
    test "returns empty list with no options" do
      assert Mix.Tasks.ExTauri.Build.build_tauri_args([], []) == []
    end

    test "adds --debug flag" do
      assert Mix.Tasks.ExTauri.Build.build_tauri_args([debug: true], []) == ["--debug"]
    end

    test "adds --target with value" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([target: "x86_64-apple-darwin"], [])
      assert args == ["--target", "x86_64-apple-darwin"]
    end

    test "adds --runner with value" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([runner: "cargo-xwin"], [])
      assert args == ["--runner", "cargo-xwin"]
    end

    test "adds --config with value" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([config: "custom.conf.json"], [])
      assert args == ["--config", "custom.conf.json"]
    end

    test "adds --bundles with value" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([bundles: "dmg,app"], [])
      assert args == ["--bundles", "dmg,app"]
    end

    test "adds --features with value" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([features: "custom-protocol"], [])
      assert args == ["--features", "custom-protocol"]
    end

    test "adds --ci flag" do
      assert Mix.Tasks.ExTauri.Build.build_tauri_args([ci: true], []) == ["--ci"]
    end

    test "adds --verbose flag" do
      assert Mix.Tasks.ExTauri.Build.build_tauri_args([verbose: true], []) == ["--verbose"]
    end

    test "combines multiple options" do
      args =
        Mix.Tasks.ExTauri.Build.build_tauri_args(
          [debug: true, target: "aarch64-apple-darwin", ci: true, verbose: true],
          []
        )

      assert "--debug" in args
      assert "--ci" in args
      assert "--verbose" in args
      assert "--target" in args
      assert "aarch64-apple-darwin" in args
    end

    test "appends extra args" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([debug: true], ["--some-extra"])
      assert args == ["--debug", "--some-extra"]
    end

    test "does not include flags for nil/false options" do
      args = Mix.Tasks.ExTauri.Build.build_tauri_args([debug: false, ci: false], [])
      assert args == []
    end
  end

  describe "Mix.Tasks.ExTauri.Dev.build_tauri_args/2" do
    test "always includes --no-dev-server-wait" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([], [])
      assert args == ["--no-dev-server-wait"]
    end

    test "adds --release flag" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([release: true], [])
      assert "--release" in args
      assert "--no-dev-server-wait" in args
    end

    test "adds --target with value" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([target: "x86_64-apple-darwin"], [])
      assert "--target" in args
      assert "x86_64-apple-darwin" in args
    end

    test "adds --no-watch flag" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([no_watch: true], [])
      assert "--no-watch" in args
    end

    test "adds --port with string value" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([port: 8080], [])
      assert "--port" in args
      assert "8080" in args
    end

    test "adds --exit-on-panic flag" do
      args = Mix.Tasks.ExTauri.Dev.build_tauri_args([exit_on_panic: true], [])
      assert "--exit-on-panic" in args
    end

    test "combines multiple options with extra args" do
      args =
        Mix.Tasks.ExTauri.Dev.build_tauri_args(
          [release: true, no_watch: true, features: "custom-protocol"],
          ["--extra"]
        )

      assert "--no-dev-server-wait" in args
      assert "--release" in args
      assert "--no-watch" in args
      assert "--features" in args
      assert "custom-protocol" in args
      assert "--extra" in args
    end
  end

  describe "Mix.Tasks.ExTauri.Info.build_tauri_args/2" do
    test "returns empty list with no options" do
      assert Mix.Tasks.ExTauri.Info.build_tauri_args([], []) == []
    end

    test "adds --interactive flag" do
      args = Mix.Tasks.ExTauri.Info.build_tauri_args([interactive: true], [])
      assert args == ["--interactive"]
    end

    test "adds --config with value" do
      args = Mix.Tasks.ExTauri.Info.build_tauri_args([config: "custom.conf.json"], [])
      assert args == ["--config", "custom.conf.json"]
    end

    test "appends extra args" do
      args = Mix.Tasks.ExTauri.Info.build_tauri_args([], ["--extra-flag"])
      assert args == ["--extra-flag"]
    end
  end

  describe "Mix.Tasks.ExTauri.Icon.build_tauri_args/2" do
    test "returns positional args only when no options" do
      assert Mix.Tasks.ExTauri.Icon.build_tauri_args([], ["icon.png"]) == ["icon.png"]
    end

    test "returns empty list with no args or options" do
      assert Mix.Tasks.ExTauri.Icon.build_tauri_args([], []) == []
    end

    test "adds --output with value" do
      args = Mix.Tasks.ExTauri.Icon.build_tauri_args([output: "assets/icons"], ["icon.png"])
      assert "icon.png" in args
      assert "--output" in args
      assert "assets/icons" in args
    end

    test "adds --config with value" do
      args = Mix.Tasks.ExTauri.Icon.build_tauri_args([config: "custom.conf.json"], [])
      assert args == ["--config", "custom.conf.json"]
    end
  end
end
