defmodule ExampleDesktopWeb.NotesLive do
  use ExampleDesktopWeb, :live_view

  alias ExampleDesktop.Notes

  def mount(params, session, socket) do
    notes = Notes.list_notes()

    selected =
      case notes do
        [] -> nil
        _ -> hd(notes)
      end

    socket = socket |> assign(notes: notes) |> assign(selected: selected)
    {:ok, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="flex w-full gap-3">
      <div class="grow-0">
        <ul>
          <li phx-click="new" phx-value-id={nil} class="bg-slate-100 p-2">New note</li>
          <li
            :for={note <- @notes}
            class={"p-2 " <>if @selected && @selected.id == note.id, do: "bg-slate-300", else: ""}
            phx-click="change"
            phx-value-id={note.id}
          >
            <%= note.title %>
          </li>
        </ul>
      </div>
      <div class="grow">
        <div :if={@selected} class="flex flex-col">
          <input type="text" phx-blur="update" phx-value-attr="title" value={@selected.title}/>
          <textarea phx-blur="update" phx-value-attr="content"><%=@selected.content%></textarea>
        </div>
        <div :if={!@selected} class="flex flex-col">
          <input type="text" phx-blur="update" phx-value-attr="title" />
          <textarea phx-blur="update" phx-value-attr="content" />
        </div>
      </div>
    </div>
    """
  end

  def handle_event("new", _, socket) do
    {:noreply, assign(socket, selected: nil)}
  end

  def handle_event("change", %{"id" => id}, socket) do
    note = Notes.get_note(id)
    {:noreply, assign(socket, selected: note)}
  end

  def handle_event(
        "update",
        %{"attr" => attr, "value" => value},
        %{assigns: %{selected: selected}} = socket
      ) do
    attrs = %{attr => value}

    {:ok, note} =
      if selected do
        Notes.update_note(selected, attrs)
      else
        Notes.add_note(attrs)
      end

    socket =
      socket
      |> assign(selected: note)
      |> assign(notes: Notes.list_notes())

    {:noreply, socket}
  end
end
