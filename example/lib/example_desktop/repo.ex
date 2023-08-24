defmodule ExampleDesktop.Repo do
  use Ecto.Repo,
    otp_app: :example_desktop,
    adapter: Ecto.Adapters.SQLite3
end
