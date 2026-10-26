defmodule ExTauri.Packager do
  @moduledoc """
  Builds the production sidecar Tauri bundles: the single executable at
  `burrito_out/<release>-<triple>` that runs your release.

  Two packagers, chosen with `config :ex_tauri, :packager`:

    * `:burrito` (default) — wraps the release with
      [Burrito](https://github.com/burrito-elixir/burrito). Every desktop
      platform, OTP 27. Add `&Burrito.wrap/1` to the release's `:steps`.

    * `:ampoule` — packs the release with
      [ampoule](https://github.com/filipecabaco/ampoule), which runs the BEAM as
      WebAssembly inside one executable: nothing is unpacked on first launch and
      the release runs on OTP 28. macOS and Linux, plus the iOS simulator (see
      `Mix.Tasks.ExTauri.Ios`). ampoule packs an ordinary release, so it builds
      with `BURRITO_SKIP=true`, the convention `mix ex_tauri.dev --sidecar
      release` already uses: a release whose `:steps` add `&Burrito.wrap/1`
      only when that is unset needs no other change.

          config :ex_tauri, :packager, :ampoule
          # optional, defaults to `ampoule` on PATH
          config :ex_tauri, :ampoule_path, "/opt/ampoule/ampoule"

  The output path stays `burrito_out/` for both, so `tauri.conf.json`'s
  `externalBin` does not change when switching. The generated shell tells the
  two apart at launch by ampoule's trailer, so `main.rs` does not either.
  """

  @arches ~w(aarch64 x86_64)

  @doc "The configured packager, `:burrito` unless set."
  @spec packager() :: :burrito | :ampoule
  def packager, do: Application.get_env(:ex_tauri, :packager, :burrito)

  @doc """
  Builds the release and writes the sidecar for the Rust target `triple`.

  Options:

    * `:packager` — overrides `packager/0`.
    * `:dest` — where an ampoule sidecar is written. Defaults to
      `burrito_out/<release>-<triple>`, where Tauri's `externalBin` looks.
  """
  @spec package(String.t(), keyword()) :: :ok
  def package(triple, opts \\ []) do
    case Keyword.get_lazy(opts, :packager, &packager/0) do
      :burrito -> package_burrito(triple)
      :ampoule -> package_ampoule(triple, opts)
      other -> Mix.raise("Unknown :packager #{inspect(other)}; expected :burrito or :ampoule")
    end
  end

  defp package_burrito(triple) do
    release = release!()

    # Run release with MIX_ENV=prod at shell level to avoid including dev config with regexes.
    # Dev config (like live_reload patterns) contains regexes that can't be serialized.
    # Must run as separate process so dependencies are loaded correctly for prod environment.
    run!("mix", ["release", release, "--overwrite"], [], """
    If you see a Burrito ERTS download error (404), you may need to configure
    a different ERTS version in your mix.exs release configuration.

    See: https://github.com/burrito-elixir/burrito#configuration
    """)

    # Burrito names output with underscores (<release>_x86_64-...) but Tauri
    # expects hyphens (<release>-x86_64-...).
    File.cp!("burrito_out/#{release}_#{triple}", "burrito_out/#{release}-#{triple}")
  end

  defp package_ampoule(triple, opts) do
    release = release!()
    dest = Keyword.get(opts, :dest, "burrito_out/#{release}-#{triple}")

    case ampoule_target(triple) do
      {:ok, target} ->
        out = Path.join(["_build", "prod", "ampoule"])
        args = ["release", "--name", release, "--target", target, "--out", out]

        run!(ampoule_path!(), args, [{"BURRITO_SKIP", "true"}], """
        ampoule needs a plain release built with the same OTP major as its
        runtime (`ampoule version` shows it), so a Burrito step in the release's
        :steps must be skipped when BURRITO_SKIP=true:

            steps: [:assemble] ++ if(System.get_env("BURRITO_SKIP") == "true", do: [], else: [&Burrito.wrap/1])

        For NIFs it also needs wasi-sdk; see https://github.com/filipecabaco/ampoule#nifs
        """)

        File.mkdir_p!(Path.dirname(dest))
        File.cp!(Path.join(out, "#{release}-#{target}"), dest)

      {:error, message} ->
        Mix.raise(message)
    end
  end

  @doc """
  The ampoule target for a Rust target triple, or why there is none.

      iex> ExTauri.Packager.ampoule_target("aarch64-apple-darwin")
      {:ok, "aarch64-darwin"}
  """
  @spec ampoule_target(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def ampoule_target(triple) do
    case String.split(triple, "-") do
      [arch, "apple", "darwin"] when arch in @arches -> {:ok, "#{arch}-darwin"}
      [arch, "unknown", "linux", _abi] when arch in @arches -> {:ok, "#{arch}-linux"}
      _ -> {:error, unsupported_target_message(triple)}
    end
  end

  defp unsupported_target_message(triple) do
    """
    ampoule cannot package for #{triple}.

    It builds for aarch64/x86_64 macOS and Linux. Use the Burrito packager for
    Windows, and build each macOS architecture separately instead of a
    universal binary.
    """
  end

  defp release! do
    release = ExTauri.release_name()

    get_in(Mix.Project.config(), [:releases, String.to_atom(release)]) ||
      raise "expected a :#{release} release configured in your mix.exs"

    release
  end

  defp ampoule_path! do
    Application.get_env(:ex_tauri, :ampoule_path) || System.find_executable("ampoule") ||
      Mix.raise("""
      ampoule not found on PATH.

      Install it from https://github.com/filipecabaco/ampoule/releases, or point
      ex_tauri at it:

          config :ex_tauri, :ampoule_path, "/path/to/ampoule"
      """)
  end

  defp run!(command, args, env, hint) do
    case System.cmd(command, args,
           env: [{"MIX_ENV", "prod"} | env],
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} ->
        :ok

      {_, exit_code} ->
        raise """
        Failed to build release with exit code #{exit_code}.

        #{hint}
        """
    end
  end
end
