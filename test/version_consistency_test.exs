defmodule ExTauri.VersionConsistencyTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Guards against version drift.

  `ExTauri.version/0` (backed by `@version` in mix.exs) is the single source
  of truth. Code paths that can read it at runtime already do; the files below
  are independent projects whose version fields cannot derive from it, so this
  test fails the build if any of them fall out of sync after a version bump.

  When bumping the package version, run:

      grep -rl '"<old>"' example website demos

  and update those `version:` / `version =` fields to match, or this test
  will tell you exactly which file drifted.
  """

  @root Path.expand("..", __DIR__)

  # {relative path, regex capturing the version in group 1}
  @mix_projects for app <- ~w(example website demos/pomodoro_farm demos/notification_hub),
                    do: {"#{app}/mix.exs", ~r/version:\s*"([^"]+)"/}

  @cargo_manifests [
    {"example/src-tauri/Cargo.toml", ~r/^\[package\].*?^version\s*=\s*"([^"]+)"/ms}
  ]

  for {path, regex} <- @mix_projects ++ @cargo_manifests do
    @path path
    @regex regex

    test "#{path} version matches the package version" do
      file = Path.join(@root, @path)

      # Skip files that aren't present in a given checkout (e.g. generated dirs).
      if File.exists?(file) do
        contents = File.read!(file)

        case Regex.run(@regex, contents) do
          [_, version] ->
            assert version == ExTauri.version(),
                   "#{@path} declares version #{inspect(version)} but the package version is " <>
                     "#{inspect(ExTauri.version())}. Update #{@path} to match after a version bump."

          nil ->
            flunk(
              "Could not find a version field in #{@path}; the guard regex may need updating."
            )
        end
      end
    end
  end
end
