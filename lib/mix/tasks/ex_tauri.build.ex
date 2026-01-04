defmodule Mix.Tasks.ExTauri.Build do
  @moduledoc """
  Builds the Tauri application for production.

  This task builds your Elixir release and compiles the Tauri application
  for production, creating distributable packages for your target platform.

  ## Usage

      $ mix ex_tauri.build [OPTIONS]

  ## Options

    * `--debug` / `-d` - Build in debug mode instead of release
    * `--target <TARGET>` - Build for the specified target triple (e.g., x86_64-apple-darwin)
    * `--runner <RUNNER>` - Use the specified runner for the binary
    * `--config <CONFIG>` - Use a custom tauri.conf.json file
    * `--bundles <BUNDLES>` - Space or comma-separated list of bundles to build (app, dmg, deb, appimage, msi, nsis, all)
    * `--features <FEATURES>` - Space or comma-separated list of Rust features to activate
    * `--ci` - Skip prompts and use CI-friendly defaults
    * `--verbose` / `-v` - Enable verbose logging

  ## Bundle Types

  The `--bundles` option accepts the following values:

    * `app` - macOS .app bundle
    * `dmg` - macOS disk image
    * `deb` - Debian package (Linux)
    * `appimage` - AppImage (Linux)
    * `msi` - MSI installer (Windows)
    * `nsis` - NSIS installer (Windows)
    * `all` - Build all applicable bundles for your platform

  ## Examples

      # Build for production (default creates platform-specific bundles)
      $ mix ex_tauri.build

      # Build in debug mode for faster builds during testing
      $ mix ex_tauri.build --debug

      # Build only a DMG for macOS
      $ mix ex_tauri.build --bundles dmg

      # Build multiple bundle types
      $ mix ex_tauri.build --bundles "dmg,app"

      # Cross-compile for a different target
      $ mix ex_tauri.build --target x86_64-pc-windows-msvc

      # Build with custom features
      $ mix ex_tauri.build --features "custom-protocol,updater"

      # CI build with verbose output
      $ mix ex_tauri.build --ci --verbose

  ## Output

  Built artifacts will be placed in `src-tauri/target/release/bundle/` directory.

  ## Platform Notes

  - **macOS**: Produces .app and optionally .dmg
  - **Linux**: Can produce .deb, .appimage, and .rpm
  - **Windows**: Can produce .msi and .exe installers

  For cross-compilation, you'll need the appropriate toolchains installed.

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Builds the Tauri application for production"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    {opts, extra_args} = OptionParser.parse!(args,
      strict: [
        debug: :boolean,
        target: :string,
        runner: :string,
        config: :string,
        bundles: :string,
        features: :string,
        ci: :boolean,
        verbose: :boolean
      ],
      aliases: [
        d: :debug,
        v: :verbose
      ]
    )

    tauri_args = build_tauri_args(opts, extra_args)
    ExTauri.run(["build" | tauri_args])
  end

  defp build_tauri_args(opts, extra_args) do
    args = []

    args = if opts[:debug], do: args ++ ["--debug"], else: args
    args = if opts[:target], do: args ++ ["--target", opts[:target]], else: args
    args = if opts[:runner], do: args ++ ["--runner", opts[:runner]], else: args
    args = if opts[:config], do: args ++ ["--config", opts[:config]], else: args
    args = if opts[:bundles], do: args ++ ["--bundles", opts[:bundles]], else: args
    args = if opts[:features], do: args ++ ["--features", opts[:features]], else: args
    args = if opts[:ci], do: args ++ ["--ci"], else: args
    args = if opts[:verbose], do: args ++ ["--verbose"], else: args

    args ++ extra_args
  end
end
