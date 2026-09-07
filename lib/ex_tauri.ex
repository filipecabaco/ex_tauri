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

  # What `mix ex_tauri.install` scaffolded for every app before the release name
  # became configurable. Kept as the default so those apps keep building.
  @default_release_name "desktop"

  use Application
  require Logger

  @doc false
  def start(_, _) do
    validate_config()

    children = [
      {Task.Supervisor, name: ExTauri.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ExTauri.Supervisor)
  end

  defp validate_config do
    otp_release = :erlang.system_info(:otp_release) |> List.to_string()

    case Integer.parse(otp_release) do
      {major, _} when major < 27 ->
        Logger.warning("""
        ExTauri requires OTP 27 but you are running OTP #{otp_release}.
        Burrito does not have pre-compiled ERTS available for other OTP versions.

        Install OTP 27 via asdf, mise, or kerl:

            asdf install erlang 27.2
        """)

      {major, _} when major > 27 ->
        Logger.warning("""
        ExTauri currently targets OTP 27 but you are running OTP #{otp_release}.
        Burrito may not have pre-compiled ERTS for OTP #{major} yet.
        Production builds may fail. Development should work if Burrito is skipped.
        """)

      _ ->
        :ok
    end

    unless Application.get_env(:ex_tauri, :version) do
      Logger.warning("""
      tauri version is not configured. Please set it in your config files:

          config :ex_tauri, :version, "#{latest_version()}"
      """)
    end

    unless Application.get_env(:ex_tauri, :app_name) do
      Logger.warning("""
      :app_name is not configured. Please set it in your config files:

          config :ex_tauri, :app_name, "My Desktop App"
      """)
    end

    for key <- [:host, :port] do
      unless Application.get_env(:ex_tauri, key) do
        Logger.warning("""
        :#{key} is not configured. This is required for ex_tauri.install and ex_tauri.dev.

            config :ex_tauri, :#{key}, #{if key == :host, do: ~s("localhost"), else: "4000"}
        """)
      end
    end
  end

  @doc """
  Returns the latest version of Tauri available.
  """
  def latest_version, do: @latest_version

  @doc """
  The name of the release Burrito wraps into the sidecar binary.

  Burrito unpacks a shipped release into `.burrito/<release>_erts-<vsn>_<app
  vsn>/`, named after the release and nothing else. `mix ex_tauri.install` used
  to scaffold that release as `:desktop` for every app it touched, so two
  ex_tauri apps on one machine shared a single unpack directory — and anything
  reasoning about a sidecar from its path alone, `ExTauri.Sidecar.Orphan`
  included, could not tell whose process it was looking at. Four sidecars of one
  app were found there and read as abandoned instances of another.

  New installs are given a name derived from the application, which makes the
  collision impossible rather than merely detectable. The default stays
  `"desktop"` so that every app installed before this keeps building, and its
  `:desktop` release keeps working untouched.

      config :ex_tauri, release_name: "my_app_desktop"
  """
  def release_name do
    :ex_tauri
    |> Application.get_env(:release_name, @default_release_name)
    |> to_string()
  end

  @doc false
  def release_name_atom, do: String.to_atom(release_name())

  @doc """
  Returns the ex_tauri package version.

  This is the single source of truth for the version (defined as
  `@version` in `mix.exs`); everything that would otherwise hardcode a
  version string derives it from here.
  """
  def version, do: Application.spec(:ex_tauri, :vsn) |> to_string()

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
  Runs a Tauri CLI command after building a full production release.

  This function builds the Elixir release (with Burrito wrapping), then
  executes the Tauri CLI. Use this for production builds only.

  For development, use `run_dev/1` which skips Burrito for faster iteration.
  For commands that don't need a release at all, use `run_simple/1`.

  ## Examples

      ExTauri.run(["build", "--target", "x86_64-apple-darwin"])

  """
  def run(args) when is_list(args) do
    check_src_tauri!()
    wrap()
    run_tauri_cli(args)
  end

  @doc """
  Runs a Tauri CLI command in development mode.

  By default (`sidecar: :phx_server`) the sidecar is a small wrapper that runs
  the configured dev-server command — `mix phx.server` unless overridden via
  `config :ex_tauri, :dev_command` — directly, so code reloading, live reload,
  and dev config work inside the Tauri window.

  Pass `sidecar: :release` to instead build a standard Elixir release (no
  Burrito) and run that as the sidecar. Use it to exercise release boot,
  runtime config, and migrations without waiting for a full production build.

  Any name registered under `config :ex_tauri, :sidecars` (or a module
  implementing `ExTauri.Sidecar`) may also be passed. See `ExTauri.Sidecar`.

  The configured `:port` is exported as `EX_TAURI_PORT` so the generated Rust
  code uses it instead of picking a free port (dev server config has a fixed
  port).

  ## Examples

      ExTauri.run_dev(["dev", "--no-dev-server-wait"])
      ExTauri.run_dev(["dev", "--no-dev-server-wait"], sidecar: :release)

  """
  def run_dev(args, opts \\ []) when is_list(args) do
    check_src_tauri!()

    opts
    |> Keyword.get(:sidecar, :phx_server)
    |> ExTauri.Sidecar.generate()

    env = [{"EX_TAURI_PORT", to_string(Application.get_env(:ex_tauri, :port, 4000))}]
    run_tauri_cli(args, env)
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

  defp run_tauri_cli(args, env \\ []) do
    opts = [
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true,
      env: env,
      # Run from project root
      cd: File.cwd!()
    ]

    case System.cmd(tauri_cli_path!(), args, opts) do
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

  # Resolves the installed Tauri CLI binary, failing with an actionable message
  # instead of an :enoent ErlangError when it was never installed.
  defp tauri_cli_path! do
    base = Path.join([installation_path(), "bin", "cargo-tauri"])

    Enum.find([base, base <> ".exe"], &File.exists?/1) ||
      raise """
      Tauri CLI not found at #{base}.

      Run the installer first:

          mix ex_tauri.install
      """
  end

  defp check_src_tauri! do
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
  end

  defp wrap() do
    release = release_name()

    get_in(Mix.Project.config(), [:releases, release_name_atom()]) ||
      raise "expected a :#{release} release configured in your mix.exs"

    # Run release with MIX_ENV=prod at shell level to avoid including dev config with regexes.
    # Dev config (like live_reload patterns) contains regexes that can't be serialized.
    # Must run as separate process so dependencies are loaded correctly for prod environment.
    case System.cmd("mix", ["release", release, "--overwrite"],
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

    # Burrito names output with underscores (<release>_x86_64-...) but Tauri
    # expects hyphens (<release>-x86_64-...). Get the host triple from rustc and
    # rename.
    rename_burrito_output()

    :ok
  end

  @doc false
  # The Rust host target triple (e.g. "aarch64-apple-darwin"), used to name the
  # sidecar that Tauri spawns. Public so `ExTauri.Sidecar` can build its context.
  def host_triplet do
    {rustc_output, 0} = System.cmd("rustc", ["-Vv"])

    case Regex.run(~r/host: (.+)/, rustc_output) do
      [_, host] -> String.trim(host)
      _ -> raise "Could not determine host triple from `rustc -Vv`"
    end
  end

  defp rename_burrito_output do
    triplet = host_triplet()
    release = release_name()

    File.cp!(
      "burrito_out/#{release}_#{triplet}",
      "burrito_out/#{release}-#{triplet}"
    )
  end
end
