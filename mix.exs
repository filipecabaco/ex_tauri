defmodule Desktop.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_tauri,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, inets: :optional, ssl: :optional],
      env: [default: []]
    ]
  end

  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :docs},
      {:burrito, github: "burrito-elixir/burrito"},
      {:jason, "~> 1.4.0"}
    ]
  end
end
