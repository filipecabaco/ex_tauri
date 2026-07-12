# Bumps the ex_tauri package version across every file that holds a version
# literal, and adds a CHANGELOG section for the new version.
#
# Dev-only tooling: lives under scripts/ (not in the mix.exs package `files`),
# so it is never shipped in the Hex package.
#
# Usage:
#
#     mix run scripts/bump_version.exs 0.3.0
#
# Runtime-derived versions (the generated Cargo.toml, test fixtures) follow
# ExTauri.version/0 automatically and are intentionally NOT touched here.
# The standalone projects below can't read that at runtime, so they're
# rewritten in place; version_consistency_test guards against drift.

defmodule BumpVersion do
  @root Path.expand("..", __DIR__)

  # {relative path, field kind}. The kind selects how the version literal is
  # spelled in that file, so we rewrite only the version field and never a
  # dependency's version (which carries a different value anyway).
  @literal_files [
    {"mix.exs", :module_attr},
    {"example/mix.exs", :mix_version},
    {"website/mix.exs", :mix_version},
    {"demos/pomodoro_farm/mix.exs", :mix_version},
    {"demos/notification_hub/mix.exs", :mix_version},
    {"example/src-tauri/Cargo.toml", :cargo_version}
  ]

  defp literal(:module_attr, version), do: ~s(@version "#{version}")
  defp literal(:mix_version, version), do: ~s(version: "#{version}")
  defp literal(:cargo_version, version), do: ~s(version = "#{version}")

  def run([new_version]) do
    validate!(new_version)
    old_version = current_version()

    if old_version == new_version do
      abort("Version is already #{new_version}; nothing to do.")
    end

    IO.puts("Bumping #{old_version} -> #{new_version}\n")

    Enum.each(@literal_files, fn {rel, kind} ->
      bump_literal(rel, literal(kind, old_version), literal(kind, new_version))
    end)

    bump_changelog(old_version, new_version)

    IO.puts("""

    Done. Next:
      - Fill in the new CHANGELOG.md section with the actual changes.
      - Run `mix test` (version_consistency_test verifies nothing drifted).
      - Commit the bump yourself.
    """)
  end

  def run(_), do: abort("Usage: mix run scripts/bump_version.exs <new-version>")

  defp current_version do
    mix_exs = File.read!(Path.join(@root, "mix.exs"))

    case Regex.run(~r/@version "([^"]+)"/, mix_exs) do
      [_, version] -> version
      nil -> abort("Could not find @version in mix.exs")
    end
  end

  defp bump_literal(rel, old_literal, new_literal) do
    path = Path.join(@root, rel)

    unless File.exists?(path) do
      IO.puts("  skip   #{rel} (missing)")
      throw(:next)
    end

    contents = File.read!(path)

    unless String.contains?(contents, old_literal) do
      abort("Expected #{inspect(old_literal)} in #{rel} but it was not found.")
    end

    File.write!(path, String.replace(contents, old_literal, new_literal))
    IO.puts("  ok     #{rel}")
  catch
    :next -> :ok
  end

  defp bump_changelog(old_version, new_version) do
    rel = "CHANGELOG.md"
    path = Path.join(@root, rel)
    contents = File.read!(path)
    today = Date.utc_today() |> Date.to_iso8601()
    repo = "https://github.com/filipecabaco/ex_tauri"

    updated =
      contents
      # Insert a stub section directly under the Unreleased heading.
      |> String.replace(
        "## [Unreleased]\n",
        "## [Unreleased]\n\n## [#{new_version}] - #{today}\n\n### Added\n\n### Changed\n\n### Fixed\n",
        global: false
      )
      # Repoint the Unreleased compare link at the new tag.
      |> String.replace(
        "[Unreleased]: #{repo}/compare/v#{old_version}...HEAD",
        "[Unreleased]: #{repo}/compare/v#{new_version}...HEAD"
      )
      # Add a release link for the new version, above the previous one.
      |> String.replace(
        "[#{old_version}]: #{repo}/releases/tag/v#{old_version}",
        "[#{new_version}]: #{repo}/releases/tag/v#{new_version}\n" <>
          "[#{old_version}]: #{repo}/releases/tag/v#{old_version}"
      )

    if updated == contents do
      IO.puts("  warn   #{rel} unchanged (check its format manually)")
    else
      File.write!(path, updated)
      IO.puts("  ok     #{rel} (added #{new_version} stub)")
    end
  end

  defp validate!(version) do
    unless version =~ ~r/^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$/ do
      abort("#{inspect(version)} is not a valid semantic version (e.g. 0.3.0).")
    end
  end

  defp abort(message) do
    IO.puts(:stderr, "Error: #{message}")
    System.halt(1)
  end
end

BumpVersion.run(System.argv())
