defmodule ExampleDesktopWeb.NotificationHubLive do
  @moduledoc """
  Unified inbox for notifications streaming in from multiple providers.

  The LiveView subscribes to `ExampleDesktop.NotificationHub`'s PubSub
  topic on mount. Every time a source process pushes a new event — or a
  user takes an action that mutates the store — a broadcast lands in
  `handle_info/2` and triggers a re-render. No polling, no websocket
  plumbing beyond LiveView's own.
  """

  use ExampleDesktopWeb, :live_view

  alias ExampleDesktop.NotificationHub

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: NotificationHub.subscribe()

    notifications = NotificationHub.inbox()

    {:ok,
     socket
     |> assign(
       filter: :all,
       show_read: true,
       selected_id: nil,
       last_event: nil,
       page_title: "Notification Hub"
     )
     |> assign_notifications(notifications)}
  end

  # ------------------------------------------------------------------
  # UI events
  # ------------------------------------------------------------------

  @impl true
  def handle_event("filter", %{"source" => source}, socket) do
    {:noreply, assign(socket, filter: to_atom(source))}
  end

  def handle_event("toggle_read_visibility", _params, socket) do
    {:noreply, assign(socket, show_read: not socket.assigns.show_read)}
  end

  def handle_event("select", %{"id" => id}, socket) do
    NotificationHub.mark_read(id)
    {:noreply, assign(socket, selected_id: id)}
  end

  def handle_event("action", %{"id" => id, "action" => action}, socket) do
    perform_action(action, id)
    {:noreply, socket}
  end

  def handle_event("mark_all_read", _params, socket) do
    NotificationHub.mark_all_read(socket.assigns.filter)
    {:noreply, socket}
  end

  def handle_event("clear", _params, socket) do
    NotificationHub.clear()
    {:noreply, socket}
  end

  # ------------------------------------------------------------------
  # PubSub: broadcasts from the store
  # ------------------------------------------------------------------

  @impl true
  def handle_info({:notification_added, notification}, socket) do
    socket =
      socket
      |> assign(last_event: {:added, notification.id})
      |> assign_notifications(NotificationHub.inbox())

    {:noreply, socket}
  end

  def handle_info(:notifications_changed, socket) do
    {:noreply, assign_notifications(socket, NotificationHub.inbox())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp assign_notifications(socket, notifications) do
    stats = NotificationHub.stats(notifications)

    assign(socket,
      notifications: notifications,
      stats: stats,
      sources: NotificationHub.source_filters()
    )
  end

  defp perform_action("mark_read", id), do: NotificationHub.mark_read(id)
  defp perform_action("dismiss", id), do: NotificationHub.dismiss(id)
  defp perform_action("snooze", id), do: NotificationHub.snooze(id, 15)
  # Primary "open" and provider-specific actions all just mark as read
  # in the demo — in a real app they'd trigger the underlying API call
  # (approve a PR, send a reply, join a huddle, etc.).
  defp perform_action(_other, id), do: NotificationHub.mark_read(id)

  defp to_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> :all
    end
  end

  defp to_atom(_), do: :all

  defp filter_notifications(notifications, filter, show_read) do
    notifications
    |> Enum.filter(fn n ->
      (filter == :all or n.source == filter) and (show_read or not n.read)
    end)
  end

  defp humanize_time(%DateTime{} = dt) do
    diff = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      diff < 5 -> "just now"
      diff < 60 -> "#{diff}s ago"
      diff < 3_600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3_600)}h ago"
      true -> "#{div(diff, 86_400)}d ago"
    end
  end

  defp source_style(:github), do: %{bg: "bg-slate-100", text: "text-slate-700", ring: "ring-slate-200"}
  defp source_style(:linear), do: %{bg: "bg-indigo-50", text: "text-indigo-700", ring: "ring-indigo-200"}
  defp source_style(:gmail), do: %{bg: "bg-rose-50", text: "text-rose-700", ring: "ring-rose-200"}
  defp source_style(:slack), do: %{bg: "bg-emerald-50", text: "text-emerald-700", ring: "ring-emerald-200"}
  defp source_style(:pomodoro), do: %{bg: "bg-amber-50", text: "text-amber-700", ring: "ring-amber-200"}
  defp source_style(_), do: %{bg: "bg-slate-100", text: "text-slate-600", ring: "ring-slate-200"}

  defp priority_badge(:urgent), do: {"Urgent", "bg-red-100 text-red-700"}
  defp priority_badge(:high), do: {"High", "bg-amber-100 text-amber-700"}
  defp priority_badge(:normal), do: {nil, nil}
  defp priority_badge(:low), do: {nil, nil}

  defp action_button_class(:primary),
    do: "bg-gradient-to-r from-indigo-500 to-purple-600 text-white hover:from-indigo-600 hover:to-purple-700 shadow-sm shadow-indigo-500/20"

  defp action_button_class(:success),
    do: "bg-emerald-500 text-white hover:bg-emerald-600 shadow-sm"

  defp action_button_class(:warning),
    do: "bg-amber-500 text-white hover:bg-amber-600 shadow-sm"

  defp action_button_class(:danger),
    do: "bg-white text-rose-600 ring-1 ring-rose-200 hover:bg-rose-50"

  defp action_button_class(_),
    do: "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"

  # ------------------------------------------------------------------
  # Template
  # ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        filtered: filter_notifications(assigns.notifications, assigns.filter, assigns.show_read)
      )

    ~H"""
    <div class="mx-auto max-w-6xl">
      <!-- Header / stats -->
      <div class="mb-6 flex flex-wrap items-center justify-between gap-4">
        <div class="flex items-center gap-3">
          <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-indigo-500 to-purple-600 shadow-lg shadow-indigo-500/25">
            <.icon name="hero-bell-alert-solid" class="h-6 w-6 text-white" />
          </div>
          <div>
            <h1 class="text-2xl font-bold text-slate-900">Notification Hub</h1>
            <p class="text-sm text-slate-500">Streaming updates from every tool you use</p>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <button
            phx-click="toggle_read_visibility"
            class="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 text-xs font-semibold text-slate-600 shadow-sm ring-1 ring-slate-200 transition hover:bg-slate-50"
          >
            <.icon
              name={if @show_read, do: "hero-eye-slash", else: "hero-eye"}
              class="h-4 w-4"
            />
            <%= if @show_read, do: "Hide read", else: "Show read" %>
          </button>
          <button
            phx-click="mark_all_read"
            class="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 text-xs font-semibold text-slate-600 shadow-sm ring-1 ring-slate-200 transition hover:bg-slate-50"
          >
            <.icon name="hero-check" class="h-4 w-4" />
            Mark all read
          </button>
          <button
            phx-click="clear"
            data-confirm="Clear every notification?"
            class="inline-flex items-center gap-1.5 rounded-xl bg-white px-3 py-2 text-xs font-semibold text-rose-600 shadow-sm ring-1 ring-rose-200 transition hover:bg-rose-50"
          >
            <.icon name="hero-trash" class="h-4 w-4" />
            Clear
          </button>
        </div>
      </div>

      <!-- Stats strip -->
      <div class="mb-6 grid gap-4 sm:grid-cols-3">
        <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-900/5">
          <p class="text-xs font-semibold uppercase tracking-wider text-slate-400">In inbox</p>
          <p class="mt-1 text-3xl font-bold text-slate-900"><%= @stats.total %></p>
        </div>
        <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-900/5">
          <p class="text-xs font-semibold uppercase tracking-wider text-slate-400">Unread</p>
          <p class="mt-1 text-3xl font-bold text-indigo-600"><%= @stats.unread %></p>
        </div>
        <div class="rounded-2xl bg-white p-4 shadow-sm ring-1 ring-slate-900/5">
          <p class="text-xs font-semibold uppercase tracking-wider text-slate-400">Needs attention</p>
          <p class="mt-1 text-3xl font-bold text-rose-600"><%= @stats.urgent %></p>
        </div>
      </div>

      <!-- Source filter chips -->
      <div class="mb-5 flex flex-wrap gap-2">
        <button
          :for={source <- @sources}
          phx-click="filter"
          phx-value-source={source.key}
          class={[
            "inline-flex items-center gap-2 rounded-full px-4 py-1.5 text-xs font-semibold transition",
            @filter == source.key && "bg-gradient-to-r from-indigo-500 to-purple-600 text-white shadow-md shadow-indigo-500/25",
            @filter != source.key && "bg-white text-slate-600 shadow-sm ring-1 ring-slate-200 hover:bg-slate-50"
          ]}
        >
          <.icon name={"#{source.icon}"} class="h-4 w-4" />
          <%= source.name %>
          <span
            :if={source.key != :all and Map.has_key?(@stats.by_source, source.key)}
            class={[
              "ml-1 rounded-full px-1.5 py-0.5 text-[10px] font-bold",
              @filter == source.key && "bg-white/20",
              @filter != source.key && "bg-slate-100 text-slate-500"
            ]}
          >
            <%= @stats.by_source[source.key].unread %>
          </span>
        </button>
      </div>

      <!-- Notifications list -->
      <div class="overflow-hidden rounded-2xl bg-white shadow-xl ring-1 ring-slate-900/5">
        <ul class="divide-y divide-slate-100">
          <li :if={@filtered == []} class="flex flex-col items-center justify-center py-16 text-slate-400">
            <.icon name="hero-inbox" class="h-16 w-16 opacity-30" />
            <p class="mt-4 text-sm font-medium">Inbox zero — waiting for the next ping…</p>
          </li>

          <li
            :for={notification <- @filtered}
            class={[
              "group relative flex gap-4 p-5 transition-colors",
              not notification.read && "bg-indigo-50/40",
              notification.read && "hover:bg-slate-50",
              @last_event == {:added, notification.id} && "animate-fade-in"
            ]}
          >
            <!-- Source badge -->
            <div class={[
              "flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-xl ring-1",
              source_style(notification.source).bg,
              source_style(notification.source).ring
            ]}>
              <.icon
                name={source_icon(notification.source)}
                class={"h-5 w-5 #{source_style(notification.source).text}"}
              />
            </div>

            <!-- Content -->
            <div class="min-w-0 flex-1">
              <div class="flex items-start justify-between gap-3">
                <div class="min-w-0">
                  <div class="flex items-center gap-2">
                    <p class={[
                      "truncate text-sm",
                      not notification.read && "font-bold text-slate-900",
                      notification.read && "font-semibold text-slate-600"
                    ]}>
                      <%= notification.title %>
                    </p>
                    <% {label, class} = priority_badge(notification.priority) %>
                    <span
                      :if={label}
                      class={"rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide #{class}"}
                    >
                      <%= label %>
                    </span>
                  </div>
                  <p class="mt-1 line-clamp-2 text-sm text-slate-500"><%= notification.body %></p>
                </div>
                <div class="flex flex-shrink-0 flex-col items-end gap-1">
                  <span class="text-[11px] font-medium text-slate-400"><%= humanize_time(notification.received_at) %></span>
                  <span
                    :if={not notification.read}
                    class="h-2 w-2 rounded-full bg-indigo-500"
                    title="Unread"
                  />
                </div>
              </div>

              <!-- Actions -->
              <div class="mt-3 flex flex-wrap gap-2">
                <button
                  :for={action <- notification.actions}
                  phx-click="action"
                  phx-value-id={notification.id}
                  phx-value-action={action.id}
                  class={[
                    "inline-flex items-center rounded-lg px-3 py-1 text-xs font-semibold transition",
                    action_button_class(action.style)
                  ]}
                >
                  <%= action.label %>
                </button>
              </div>
            </div>
          </li>
        </ul>
      </div>

      <p class="mt-6 text-center text-xs text-slate-400">
        Each provider is its own supervised <code class="rounded bg-slate-100 px-1 py-0.5">GenServer</code> —
        kill one in IEx and the rest keep streaming.
      </p>
    </div>
    """
  end

  defp source_icon(:github), do: "hero-code-bracket"
  defp source_icon(:linear), do: "hero-queue-list"
  defp source_icon(:gmail), do: "hero-envelope"
  defp source_icon(:slack), do: "hero-chat-bubble-left-right"
  defp source_icon(:pomodoro), do: "hero-clock"
  defp source_icon(_), do: "hero-bell"
end
