defmodule ExTauriWebsite.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_tauri_website,
      version: "0.1.0",
      elixir: "~> 1.14",
      elixirc_paths: ["lib"],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [mod: {ExTauriWebsite, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:francis, "~> 0.3"}
    ]
  end

  defp aliases do
    [
      "assets.deploy": ["francis.digest"]
    ]
  end
end
