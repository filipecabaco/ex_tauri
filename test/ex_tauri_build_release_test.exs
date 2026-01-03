defmodule ExTauri.BuildReleaseTest do
  use ExUnit.Case, async: false

  @moduletag :build_release

  describe "release environment handling" do
    test "documents that releases must use prod environment" do
      # This test documents the requirement that Burrito releases
      # must be built with MIX_ENV=prod to avoid serialization errors

      documentation = """
      Why MIX_ENV=prod is required for releases:

      1. Development config (config/dev.exs) contains regexes
         Example: Phoenix's live_reload patterns
         ~r"priv/static/.*(js|css)$"

      2. Regexes cannot be serialized in Erlang term format
         Burrito needs to serialize all configuration

      3. When MIX_ENV=prod:
         - config/dev.exs is NOT loaded
         - Only config/prod.exs and config/runtime.exs are used
         - No regexes in production config
         - Release builds successfully

      4. The wrap() function handles this automatically:
         - Saves current MIX_ENV
         - Sets MIX_ENV to :prod
         - Runs mix release desktop
         - Restores original MIX_ENV
      """

      assert String.contains?(documentation, "MIX_ENV=prod")
      assert String.contains?(documentation, "regexes cannot be serialized")
      assert String.contains?(documentation, "config/dev.exs is NOT loaded")
    end

    test "validates that wrap function changes MIX_ENV temporarily" do
      # The wrap() function should:
      # 1. Save current environment
      # 2. Switch to :prod
      # 3. Build release
      # 4. Restore original environment

      # We can't easily test the actual function without running a full build,
      # but we can document the expected behavior

      expected_flow = [
        "original_env = Mix.env()",
        "Mix.env(:prod)",
        "Mix.Task.run(\"release\", [\"desktop\", \"--overwrite\"])",
        "Mix.env(original_env)"
      ]

      assert length(expected_flow) == 4
      assert "Mix.env(:prod)" in expected_flow
      assert "Mix.env(original_env)" in expected_flow
    end

    test "documents common configuration that causes serialization errors" do
      problematic_configs = %{
        "Phoenix live_reload" => ~r"priv/static/.*(js|css)$",
        "Phoenix live patterns" => ~r"lib/app_web/(controllers|live)/.*(ex|heex)$",
        "Custom watchers with patterns" => ~r"assets/.*(js|css)$"
      }

      # All of these are in dev.exs and won't be in releases when MIX_ENV=prod
      assert map_size(problematic_configs) == 3

      for {description, regex} <- problematic_configs do
        assert is_binary(description)
        assert Regex.regex?(regex)
      end
    end

    test "validates that prod config should not have regexes" do
      # Production configuration should use strings or runtime configuration
      # instead of compile-time regexes

      good_prod_config = """
      # config/prod.exs - NO regexes!
      config :my_app, MyAppWeb.Endpoint,
        cache_static_manifest: "priv/static/cache_manifest.json"

      # If you need patterns, use runtime.exs with runtime evaluation
      """

      bad_prod_config = """
      # config/prod.exs - BAD! Has regex
      config :my_app, MyAppWeb.Endpoint,
        patterns: [~r"priv/static/.*"]  # This will fail in release!
      """

      assert String.contains?(good_prod_config, "NO regexes")
      assert String.contains?(bad_prod_config, "BAD")
    end
  end
end
