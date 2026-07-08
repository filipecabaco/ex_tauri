defmodule ExTauri.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/filipecabaco/ex_tauri"

  def project do
    [
      app: :ex_tauri,
      version: @version,
      elixir: "~> 1.15",
      # Limited to OTP 27 due to Burrito pre-compiled ERTS availability
      # OTP 28 doesn't have universal macOS binaries available yet
      otp_release: "~> 27.0",
      start_permanent: Mix.env() == :prod,
      description: "Build native desktop applications with Phoenix and Elixir, powered by Tauri",
      package: package(),
      docs: docs(),
      deps: deps()
    ]
  end

  def application do
    [
      mod: {ExTauri, []},
      extra_applications: [:logger, inets: :optional, ssl: :optional]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib priv guides .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "guides/releasing.md"]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:burrito, "~> 1.5"},
      {:igniter, "~> 0.7"},
      {:jason, "~> 1.4"}
    ]
  end
end
