defmodule ExTauri.MixProject do
  use Mix.Project

  @version "0.5.2"
  @source_url "https://github.com/filipecabaco/ex_tauri"

  def project do
    [
      app: :ex_tauri,
      version: @version,
      elixir: "~> 1.17",
      # No OTP pin here: Burrito builds need OTP 27 and ampoule (and iOS) OTP 28,
      # which ExTauri checks at boot for the packager in use (lib/ex_tauri.ex).
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
      files:
        ~w(lib priv guides .formatter.exs mix.exs README.md LICENSE CHANGELOG.md usage-rules.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md", "guides/releasing.md", "guides/ios.md"]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      # Build tools, used only by the mix tasks and the Burrito release step:
      # runtime: false keeps them, and everything they pull in (rewrite,
      # sourceror, owl, req...), out of every app's packaged release.
      {:burrito, "~> 1.6", runtime: false},
      {:igniter, "~> 0.7", runtime: false},
      {:jason, "~> 1.4"}
    ]
  end
end
