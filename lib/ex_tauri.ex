defmodule ExTauri do
  @moduledoc """
  ExTauri provides integration between Phoenix and Tauri for building
  native desktop applications.

  This module provides core functionality for running Tauri commands and
  managing the Tauri installation. For installation and setup, use
  `Mix.Tasks.ExTauri.Install`. For running commands, use the dedicated
  Mix tasks like `Mix.Tasks.ExTauri.Dev` and `Mix.Tasks.ExTauri.Build`.
  """

  @latest_version "2.5.1"

  use Application
  require Logger

  @doc false
  def start(_, _) do
    unless Application.get_env(:ex_tauri, :version) do
      Logger.warning("""
      tauri version is not configured. Please set it in your config files:

          config :ex_tauri, :version, "#{latest_version()}"
      """)
    end

    Supervisor.start_link([], strategy: :one_for_one)
  end

  @doc """
  Returns the latest version of Tauri available.
  """
  def latest_version, do: @latest_version

  @doc """
  Returns the path to the Tauri installation.

  The executable may not be available if it was not yet installed.
  """
  def installation_path do
    Application.get_env(:ex_tauri, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), "_tauri")
      else
        Path.expand("_build/_tauri")
      end
  end

  @doc """
  Runs a Tauri CLI command with the given arguments.

  This function builds the Elixir release using Burrito, then executes
  the Tauri CLI with the provided arguments. Use this for commands that
  require a sidecar binary (dev, build).

  For commands that don't need the release build, use `run_simple/1`.

  ## Examples

      ExTauri.run(["dev"])
      ExTauri.run(["build", "--target", "x86_64-apple-darwin"])

  """
  def run(args) when is_list(args) do
    # Verify we're in a directory with src-tauri before proceeding
    unless File.dir?("src-tauri") do
      raise """
      Could not find src-tauri directory in the current path: #{File.cwd!()}

      Make sure you:
      1. Run this command from your project root (where mix.exs is located)
      2. Have run 'mix ex_tauri.install' to set up the Tauri project structure

      If you're in the ex_tauri repository root, try:
        cd example
        mix ex_tauri.build
      """
    end

    wrap()
    run_tauri_cli(args)
  end

  @doc """
  Runs a Tauri CLI command without building the Elixir release.

  Use this for commands that don't require a sidecar binary, such as:
  - `info` - Display project information
  - `icon` - Generate application icons
  - `signer` - Manage code signing

  ## Examples

      ExTauri.run_simple(["info"])
      ExTauri.run_simple(["icon", "app-icon.png"])

  """
  def run_simple(args) when is_list(args) do
    run_tauri_cli(args)
  end

  # Private functions

  defp run_tauri_cli(args) do
    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true,
      # Run from project root
      cd: File.cwd!()
    ]

    case [installation_path(), "bin", "cargo-tauri"]
         |> Path.join()
         |> System.cmd(args, opts) do
      {_, 0} ->
        :ok

      {_, exit_code} ->
        raise """
        Tauri command failed with exit code #{exit_code}.

        Make sure you have a valid Tauri project and that all dependencies
        are properly installed.
        """
    end
  end

  defp wrap() do
    File.rm_rf!(Path.join([Path.expand("~"), "Library", "Application Support", ".burrito"]))

    get_in(Mix.Project.config(), [:releases, :desktop]) ||
      raise "expected a burrito release configured for the app :desktop in your mix.exs"

    # Run release with MIX_ENV=prod at shell level to avoid including dev config with regexes
    # Dev config (like live_reload patterns) contains regexes that can't be serialized
    # Must run as separate process so dependencies are loaded correctly for prod environment
    case System.cmd("mix", ["release", "desktop", "--overwrite"],
      env: [{"MIX_ENV", "prod"}],
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ) do
      {_, 0} ->
        :ok

      {_, exit_code} ->
        raise """
        Failed to build release with exit code #{exit_code}.

        If you see a Burrito ERTS download error (404), you may need to configure
        a different ERTS version in your mix.exs release configuration.

        See: https://github.com/burrito-elixir/burrito#configuration
        """
    end

    triplet =
      System.cmd("rustc", ["-Vv"])
      |> elem(0)
      |> then(&Regex.run(~r/host: (.*)/, &1))
      |> Enum.at(1)

    File.cp!(
      "burrito_out/desktop_#{triplet}",
      "burrito_out/desktop-#{triplet}"
    )

    :ok
  end
end
