defmodule ExampleDesktop.Repo.Migrations.AddNotes do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:notes) do
      add(:content, :string)
      add(:title, :string)
      timestamps()
    end
  end
end
