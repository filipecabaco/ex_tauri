defmodule ExTauri.TaskHelpers do
  @moduledoc false
  # Shared utilities for ExTauri Mix tasks.

  @doc """
  Validates that the Tauri project is set up and Rust toolchain is available.
  Raises with actionable error messages if anything is missing.
  """
  def preflight_check! do
    unless File.dir?("src-tauri") do
      Mix.raise("""
      Tauri project not found. Run this first:

          mix ex_tauri.install
      """)
    end

    unless System.find_executable("cargo") do
      Mix.raise("""
      Rust/Cargo is not installed or not in your PATH.

      Install Rust: https://www.rust-lang.org/tools/install

          curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
      """)
    end
  end

  @doc """
  Builds Tauri CLI arguments from parsed options.

  Accepts a keyword list of `{flag_name, value}` pairs and extra passthrough args.
  Boolean flags are included when `true`, string flags include their value.
  """
  def build_tauri_args(flag_specs, opts, extra_args) do
    flag_args =
      Enum.flat_map(flag_specs, fn {key, flag} ->
        case opts[key] do
          true -> [flag]
          nil -> []
          false -> []
          value when is_binary(value) -> [flag, value]
          value -> [flag, to_string(value)]
        end
      end)

    flag_args ++ extra_args
  end
end
