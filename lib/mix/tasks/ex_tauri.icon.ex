defmodule Mix.Tasks.ExTauri.Icon do
  @moduledoc """
  Generates application icons from a source image.

  This task takes a source image and generates all the required icon sizes
  and formats for your Tauri application across different platforms (macOS, Windows, Linux).

  ## Usage

      $ mix ex_tauri.icon [INPUT] [OPTIONS]

  ## Arguments

    * `INPUT` - Path to the source icon image (PNG recommended, minimum 1024x1024px)
                If not provided, will look for `app-icon.png` in the project root

  ## Options

    * `--output <DIR>` / `-o <DIR>` - Output directory for generated icons (default: src-tauri/icons)
    * `--config <CONFIG>` - Use a custom tauri.conf.json file

  ## Examples

      # Generate icons from app-icon.png (default)
      $ mix ex_tauri.icon

      # Generate icons from a specific file
      $ mix ex_tauri.icon path/to/my-icon.png

      # Generate icons to a custom directory
      $ mix ex_tauri.icon my-icon.png --output assets/icons

  ## Requirements

  Your source image should:
  - Be a PNG file
  - Have a square aspect ratio (1:1)
  - Be at least 1024x1024 pixels for best quality
  - Have a transparent background (for best results)
  - Avoid very fine details that won't render well at small sizes

  ## Generated Icons

  This command will generate icons in multiple sizes and formats:

  - **macOS**: .icns file with multiple resolutions
  - **Windows**: .ico file with multiple resolutions
  - **Linux**: PNG files in various sizes (32x32, 128x128, 256x256, 512x512)
  - **iOS/Android**: Additional sizes if mobile targets are configured

  ## Tips

  - Use a simple, recognizable design for your icon
  - Ensure good contrast for visibility at small sizes
  - Test the generated icons on different platforms
  - Keep a backup of your source icon at high resolution

  For more information, see: https://github.com/filipecabaco/ex_tauri
  """

  @shortdoc "Generates application icons from a source image"
  @compile {:no_warn_undefined, Mix}

  use Mix.Task

  @impl true
  def run(args) do
    {opts, positional_args} = OptionParser.parse!(args,
      strict: [
        output: :string,
        config: :string
      ],
      aliases: [
        o: :output
      ]
    )

    tauri_args = build_tauri_args(opts, positional_args)
    ExTauri.run_simple(["icon" | tauri_args])
  end

  defp build_tauri_args(opts, positional_args) do
    args = positional_args

    args = if opts[:output], do: args ++ ["--output", opts[:output]], else: args
    args = if opts[:config], do: args ++ ["--config", opts[:config]], else: args

    args
  end
end
