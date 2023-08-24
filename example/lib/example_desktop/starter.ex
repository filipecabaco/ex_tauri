defmodule ExampleDesktop.Starter do
  alias ExampleDesktop.Repo

  def run() do
    Application.ensure_all_started(:ecto_sql)
    Repo.__adapter__().storage_up(Repo.config())
    Ecto.Migrator.run(Repo, :up, all: true)
  end
end
