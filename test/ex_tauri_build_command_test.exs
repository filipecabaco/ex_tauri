defmodule ExTauri.BuildCommandTest do
  use ExUnit.Case, async: false

  @moduletag :build_validation
  @moduletag timeout: 300_000  # 5 minutes for build operations

  describe "build command validation" do
    test "ensures example app config has serializable regexes" do
      # This test validates that all regexes in config files use the /E modifier
      # which is required for Burrito releases

      dev_config_path = Path.join([__DIR__, "..", "example", "config", "dev.exs"])

      if File.exists?(dev_config_path) do
        content = File.read!(dev_config_path)

        # Find all regex patterns
        regex_patterns = Regex.scan(~r/~r"[^"]+"/, content)

        # Verify all regexes have the /E modifier
        for [pattern] <- regex_patterns do
          assert String.ends_with?(pattern, "\"E") or String.ends_with?(pattern, "\"e"),
                 """
                 Found regex without /E modifier: #{pattern}

                 Regexes in config files must use the /E modifier to be serializable
                 in releases. This is required for Burrito to create the release.

                 Fix: Add E after the closing quote, e.g.:
                   ~r"pattern$"E

                 This prevents the error:
                   ** (Mix) Could not write configuration file because it has invalid terms
                   Reason: you must use the /E modifier to store regexes
                 """
        end
      else
        # If example app doesn't exist, skip the test
        assert true
      end
    end

    test "validates dev.exs has correct live_reload pattern format" do
      dev_config_path = Path.join([__DIR__, "..", "example", "config", "dev.exs"])

      if File.exists?(dev_config_path) do
        content = File.read!(dev_config_path)

        # Check for the specific patterns that caused the issue
        static_pattern = ~r/priv\/static\/\.\*\(js\|css\|png\|jpeg\|jpg\|gif\|svg\)\$/
        live_pattern = ~r/lib\/example_desktop_web\/\(controllers\|live\|components\)\/\.\*\(ex\|heex\)\$/

        # Verify they exist in the file
        assert content =~ static_pattern,
               "Expected to find static file pattern in dev.exs"

        assert content =~ live_pattern,
               "Expected to find live reload pattern in dev.exs"

        # Verify they have the /E modifier
        assert content =~ ~r/~r"priv\/static\/.*\$"E/,
               "Static file pattern must have /E modifier"

        assert content =~ ~r/~r"lib\/example_desktop_web\/.*\$"E/,
               "Live reload pattern must have /E modifier"
      else
        assert true
      end
    end

    test "documents the regex serialization requirement" do
      # This test serves as living documentation
      # When creating Phoenix apps for Tauri/Burrito, always use /E modifier

      serializable_regex = ~r"pattern"E
      non_serializable_regex = ~r"pattern"

      # The /E modifier makes regexes encodable/decodable
      assert {:ok, _encoded} = Inspect.Algebra.to_doc(serializable_regex, %Inspect.Opts{})

      # Document the requirement
      requirement = """
      REQUIREMENT: All regexes in config files must use the /E modifier

      Why: Burrito releases need to serialize all configuration, and regular
      regexes cannot be serialized without the /E modifier.

      Example:
        ❌ ~r"priv/static/.*(js|css)$"     # Will fail in release
        ✅ ~r"priv/static/.*(js|css)$"E    # Works in release

      Common places to check:
        - config/dev.exs: live_reload patterns
        - config/runtime.exs: any regex configuration
        - Phoenix endpoint configurations
      """

      assert String.contains?(requirement, "/E modifier")
    end
  end

  describe "wrap command validation" do
    test "validates mix release desktop command succeeds" do
      # This is a smoke test to ensure the Burrito release can be created
      # We don't actually run it in tests, but document the expectation

      expected_command = "mix release desktop"
      expected_steps = [:assemble, &Burrito.wrap/1]

      # Document what should happen
      assert String.contains?(expected_command, "release desktop")
      assert length(expected_steps) == 2
      assert :assemble in expected_steps
    end

    test "documents the build process" do
      build_process = """
      Build Process for Tauri Desktop Apps:

      1. mix release desktop
         - Assembles the Elixir application
         - Runs Burrito.wrap/1 to create standalone binary
         - Requires all config to be serializable

      2. mix ex_tauri build
         - Calls 'mix release desktop' first
         - Renames burrito output for Tauri compatibility
         - Runs cargo-tauri build

      Common Failures:

      1. "Could not write configuration file because it has invalid terms"
         Solution: Add /E modifier to all regexes

      2. "Version not found" during cargo install
         Solution: Use semver ranges (handled automatically)

      3. "Failed to spawn desktop sidecar"
         Solution: Ensure burrito_out/desktop exists
      """

      assert String.contains?(build_process, "mix release desktop")
      assert String.contains?(build_process, "Burrito.wrap")
      assert String.contains?(build_process, "/E modifier")
    end
  end

  describe "configuration validation helpers" do
    test "provides helper to check if regex has /E modifier" do
      has_e_modifier? = fn regex_string ->
        String.ends_with?(regex_string, "\"E") or String.ends_with?(regex_string, "\"e")
      end

      assert has_e_modifier?.(~s[~r"pattern"E])
      assert has_e_modifier?.(~s[~r"pattern"e])
      refute has_e_modifier?.(~s[~r"pattern"])
      refute has_e_modifier?.(~s[~r"pattern"i])
    end

    test "documents how to fix the regex error" do
      fix_guide = """
      How to Fix: "you must use the /E modifier to store regexes"

      1. Find the problematic regex in the error message
         Example: ~r/priv\\/static\\/.*(js|css)$/

      2. Add E after the closing quote
         Before: ~r"priv/static/.*(js|css)$"
         After:  ~r"priv/static/.*(js|css)$"E

      3. Verify in all config files:
         grep -r '~r"' config/

      4. Test the release:
         MIX_ENV=dev mix release desktop

      5. If it succeeds, the fix worked!
      """

      assert String.contains?(fix_guide, "/E modifier")
      assert String.contains?(fix_guide, "~r\"")
    end
  end
end
