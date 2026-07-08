defmodule ExTauriWebsite do
  @moduledoc """
  OTP application for the ExTauri showcase website, served by Francis.
  """
  use Application

  def start(_type, _args) do
    children = [
      ExTauriWebsite.Router
    ]

    opts = [strategy: :one_for_one, name: ExTauriWebsite.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
