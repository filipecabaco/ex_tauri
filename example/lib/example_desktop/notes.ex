defmodule ExampleDesktop.Notes do
  alias ExampleDesktop.Repo
  alias ExampleDesktop.Notes.Note

  def add_note(attrs) do
    %Note{}
    |> Note.changeset(attrs)
    |> Repo.insert()
  end

  def update_note(%Note{} = note, attrs) do
    note
    |> Note.changeset(attrs)
    |> IO.inspect()
    |> Repo.update()
  end

  def list_notes() do
    Repo.all(Note)
  end

  def get_note(id) do
    Repo.get(Note, id)
  end
end
