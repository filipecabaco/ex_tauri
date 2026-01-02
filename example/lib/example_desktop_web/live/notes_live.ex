defmodule ExampleDesktopWeb.NotesLive do
  use ExampleDesktopWeb, :live_view

  alias ExampleDesktop.Notes

  def mount(_params, _session, socket) do
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
    <div class="flex h-[calc(100vh-6rem)] w-full overflow-hidden rounded-2xl bg-white shadow-xl ring-1 ring-slate-900/5">
      <!-- Sidebar -->
      <div class="w-80 flex-shrink-0 border-r border-slate-200 bg-gradient-to-b from-slate-50 to-white">
        <!-- New Note Button -->
        <div class="border-b border-slate-200 p-4">
          <button
            phx-click="new"
            phx-value-id={nil}
            class="group flex w-full items-center justify-center gap-2 rounded-xl bg-gradient-to-r from-indigo-500 to-purple-600 px-4 py-3 text-sm font-semibold text-white shadow-lg shadow-indigo-500/30 transition-all duration-200 hover:from-indigo-600 hover:to-purple-700 hover:shadow-indigo-500/40 active:scale-95"
          >
            <.icon name="hero-plus-solid" class="h-5 w-5 transition-transform group-hover:rotate-90" />
            New Note
          </button>
        </div>

        <!-- Notes List -->
        <ul class="custom-scrollbar overflow-y-auto p-3">
          <li
            :for={note <- @notes}
            phx-click="change"
            phx-value-id={note.id}
            class={["group relative mb-2 cursor-pointer rounded-xl p-4 transition-all duration-200 animate-fade-in",
              @selected && @selected.id == note.id
                && "bg-gradient-to-r from-indigo-500 to-purple-600 text-white shadow-lg shadow-indigo-500/20",
              !(@selected && @selected.id == note.id)
                && "bg-white hover:bg-slate-50 hover:shadow-md"]}
          >
            <div class="flex items-start justify-between gap-2">
              <div class="flex-1 min-w-0">
                <p class={[
                  "truncate text-sm font-semibold transition-colors",
                  @selected && @selected.id == note.id && "text-white",
                  !(@selected && @selected.id == note.id) && "text-slate-900"
                ]}>
                  <%= note.title || "Untitled Note" %>
                </p>
                <p class={[
                  "mt-1 truncate text-xs transition-colors",
                  @selected && @selected.id == note.id && "text-indigo-100",
                  !(@selected && @selected.id == note.id) && "text-slate-500"
                ]}>
                  <%= if String.length(note.content || "") > 50 do
                    String.slice(note.content, 0, 50) <> "..."
                  else
                    note.content || "No content"
                  end %>
                </p>
              </div>
              <.icon
                name="hero-chevron-right-solid"
                class={[
                  "h-5 w-5 flex-shrink-0 transition-all duration-200",
                  @selected && @selected.id == note.id && "opacity-100 rotate-0",
                  !(@selected && @selected.id == note.id) && "opacity-0 group-hover:opacity-100 -rotate-90"
                ]}
              />
            </div>
          </li>
          <li :if={@notes == []} class="flex flex-col items-center justify-center py-12 text-slate-400 animate-fade-in">
            <.icon name="hero-document-text" class="h-16 w-16 opacity-20" />
            <p class="mt-4 text-sm font-medium">No notes yet</p>
            <p class="mt-1 text-xs">Create your first note to get started</p>
          </li>
        </ul>
      </div>

      <!-- Main Content Area -->
      <div class="flex flex-1 flex-col bg-white">
        <div :if={@selected} class="flex flex-1 flex-col animate-fade-in">
          <!-- Header -->
          <div class="border-b border-slate-200 bg-gradient-to-b from-slate-50 to-white px-8 py-6">
            <div class="flex items-center gap-3">
              <div class="flex h-10 w-10 items-center justify-center rounded-xl bg-gradient-to-br from-indigo-500 to-purple-600 shadow-lg shadow-indigo-500/20">
                <.icon name="hero-pencil-solid" class="h-5 w-5 text-white" />
              </div>
              <div>
                <h1 class="text-sm font-semibold text-slate-400 uppercase tracking-wider">Editing Note</h1>
                <p class="text-xs text-slate-400">Last updated just now</p>
              </div>
            </div>
          </div>

          <!-- Title Input -->
          <div class="px-8 pt-8">
            <input
              type="text"
              phx-blur="update"
              phx-value-attr="title"
              value={@selected.title}
              placeholder="Note title..."
              class="w-full bg-transparent text-3xl font-bold text-slate-900 placeholder:text-slate-300 focus:outline-none focus:ring-0"
            />
          </div>

          <!-- Content Textarea -->
          <div class="flex-1 px-8 pb-8">
            <textarea
              phx-blur="update"
              phx-value-attr="content"
              placeholder="Start typing your note..."
              class="custom-scrollbar h-full w-full resize-none bg-transparent text-lg text-slate-600 placeholder:text-slate-300 focus:outline-none focus:ring-0 leading-relaxed"
            ><%=@selected.content%></textarea>
          </div>
        </div>

        <!-- New Note State -->
        <div :if={!@selected} class="flex flex-1 flex-col items-center justify-center animate-fade-in">
          <div class="mb-6 flex h-24 w-24 items-center justify-center rounded-full bg-gradient-to-br from-indigo-100 to-purple-100">
            <.icon name="hero-plus-solid" class="h-12 w-12 text-indigo-500" />
          </div>
          <h2 class="mb-2 text-2xl font-bold text-slate-900">Create a New Note</h2>
          <p class="mb-8 text-center text-slate-500">
            Click "New Note" in the sidebar<br />to start writing
          </p>
          <div class="flex items-center gap-4 rounded-xl bg-slate-50 px-6 py-4 text-sm text-slate-500">
            <.icon name="hero-light-bulb-solid" class="h-5 w-5 text-amber-500" />
            <span>Tips: Use clear titles to organize your notes</span>
          </div>
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
    attrs = Map.put(%{}, String.to_existing_atom(attr), value)

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
