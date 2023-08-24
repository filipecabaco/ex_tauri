defmodule ExampleDesktop.Notes.Note do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notes" do
    field(:content, :string)
    field(:title, :string)
    timestamps()
  end

  def changeset(note, attrs) do
    cast(note, attrs, [:title, :content])
  end
end
