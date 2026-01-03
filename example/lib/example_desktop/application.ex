defmodule ExampleDesktop.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias ExampleDesktop.Repo
  @impl true
  def start(_type, _args) do
    children = [
      Repo,
      {Phoenix.PubSub, name: ExampleDesktop.PubSub},
      ExampleDesktopWeb.Endpoint,
      ExTauri.ShutdownManager
    ]

    opts = [strategy: :one_for_one, name: ExampleDesktop.Supervisor]
    start = Supervisor.start_link(children, opts)

    ExampleDesktop.Starter.run()
    start
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ExampleDesktopWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
