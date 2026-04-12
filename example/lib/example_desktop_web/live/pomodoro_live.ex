defmodule ExampleDesktopWeb.PomodoroLive do
  @moduledoc """
  Demo LiveView for the Pomodoro timer farm.

  Every timer on screen is backed by its own supervised `GenServer`.
  When the user starts a new preset we ask the `DynamicSupervisor` to
  spawn one. Updates flow back through `Phoenix.PubSub` so the list
  re-renders as timers tick, pause, reset and complete — all without
  the LiveView ever holding a single timer reference itself.
  """

  use ExampleDesktopWeb, :live_view

  alias ExampleDesktop.Pomodoros

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Pomodoros.subscribe()

    {:ok,
     socket
     |> assign(
       presets: Pomodoros.presets(),
       custom_label: "",
       custom_minutes: "25",
       page_title: "Pomodoro Farm"
     )
     |> assign_timers(Pomodoros.list())}
  end

  # ------------------------------------------------------------------
  # UI events
  # ------------------------------------------------------------------

  @impl true
  def handle_event("start_preset", %{"index" => index}, socket) do
    preset = Enum.at(socket.assigns.presets, String.to_integer(index))

    if preset do
      Pomodoros.start_timer(%{label: preset.label, duration_s: preset.duration_s})
    end

    {:noreply, socket}
  end

  def handle_event("update_custom", %{"label" => label, "minutes" => minutes}, socket) do
    {:noreply, assign(socket, custom_label: label, custom_minutes: minutes)}
  end

  def handle_event("start_custom", %{"label" => label, "minutes" => minutes}, socket) do
    with {mins, _} when mins > 0 <- Integer.parse(minutes || ""),
         label when label != "" <- String.trim(label || "") do
      Pomodoros.start_timer(%{label: label, duration_s: mins * 60})
      {:noreply, assign(socket, custom_label: "", custom_minutes: "25")}
    else
      _ ->
        {:noreply, put_flash(socket, :error, "Please provide a label and a positive duration.")}
    end
  end

  def handle_event("toggle", %{"id" => id}, socket) do
    Pomodoros.toggle(id)
    {:noreply, socket}
  end

  def handle_event("reset", %{"id" => id}, socket) do
    Pomodoros.reset(id)
    {:noreply, socket}
  end

  def handle_event("stop", %{"id" => id}, socket) do
    Pomodoros.stop(id)
    {:noreply, socket}
  end

  # ------------------------------------------------------------------
  # PubSub broadcasts
  # ------------------------------------------------------------------

  @impl true
  def handle_info({event, _payload}, socket)
      when event in [:timer_started, :timer_updated, :timer_completed] do
    {:noreply, assign_timers(socket, Pomodoros.list())}
  end

  def handle_info({:timer_removed, _id}, socket) do
    {:noreply, assign_timers(socket, Pomodoros.list())}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp assign_timers(socket, timers) do
    assign(socket,
      timers: timers,
      running: Enum.count(timers, &(&1.status == :running)),
      paused: Enum.count(timers, &(&1.status == :paused)),
      completed: Enum.count(timers, &(&1.status == :completed))
    )
  end

  defp format_time(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> IO.iodata_to_binary()
  end

  defp progress(%{duration_s: 0}), do: 0
  defp progress(%{duration_s: duration_s, remaining_s: remaining_s}) do
    round((duration_s - remaining_s) / duration_s * 100)
  end

  defp status_badge(:running), do: {"Running", "bg-emerald-100 text-emerald-700"}
  defp status_badge(:paused), do: {"Paused", "bg-amber-100 text-amber-700"}
  defp status_badge(:completed), do: {"Done", "bg-indigo-100 text-indigo-700"}

  # ------------------------------------------------------------------
  # Template
  # ------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-5xl">
      <!-- Header -->
      <div class="mb-6 flex items-center justify-between">
        <div class="flex items-center gap-3">
          <div class="flex h-12 w-12 items-center justify-center rounded-2xl bg-gradient-to-br from-rose-500 to-orange-500 shadow-lg shadow-rose-500/25">
            <.icon name="hero-clock-solid" class="h-6 w-6 text-white" />
          </div>
          <div>
            <h1 class="text-2xl font-bold text-slate-900">Pomodoro Farm</h1>
            <p class="text-sm text-slate-500">One GenServer per timer, all ticking in parallel</p>
          </div>
        </div>

        <div class="flex gap-2 text-xs font-semibold">
          <span class="rounded-full bg-emerald-100 px-3 py-1 text-emerald-700">
            Running <%= @running %>
          </span>
          <span class="rounded-full bg-amber-100 px-3 py-1 text-amber-700">
            Paused <%= @paused %>
          </span>
          <span class="rounded-full bg-indigo-100 px-3 py-1 text-indigo-700">
            Done <%= @completed %>
          </span>
        </div>
      </div>

      <!-- Presets + custom starter -->
      <div class="mb-6 rounded-2xl bg-white p-5 shadow-xl ring-1 ring-slate-900/5">
        <p class="mb-3 text-xs font-semibold uppercase tracking-wider text-slate-400">Quick start</p>
        <div class="flex flex-wrap gap-2">
          <button
            :for={{preset, idx} <- Enum.with_index(@presets)}
            phx-click="start_preset"
            phx-value-index={idx}
            class="inline-flex items-center gap-2 rounded-xl bg-gradient-to-r from-rose-500 to-orange-500 px-4 py-2 text-sm font-semibold text-white shadow-md shadow-rose-500/20 transition hover:from-rose-600 hover:to-orange-600 active:scale-95"
          >
            <.icon name="hero-play-solid" class="h-4 w-4" />
            <%= preset.label %>
            <span class="rounded-full bg-white/20 px-2 py-0.5 text-[10px] font-bold">
              <%= div(preset.duration_s, 60) %>m
            </span>
          </button>
        </div>

        <form
          phx-change="update_custom"
          phx-submit="start_custom"
          class="mt-5 flex flex-wrap items-end gap-3"
        >
          <div class="flex-1 min-w-[200px]">
            <label class="mb-1 block text-xs font-semibold uppercase tracking-wider text-slate-400">
              Custom label
            </label>
            <input
              type="text"
              name="label"
              value={@custom_label}
              placeholder="Write blog post"
              class="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-900 placeholder:text-slate-300 focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-100"
            />
          </div>
          <div class="w-32">
            <label class="mb-1 block text-xs font-semibold uppercase tracking-wider text-slate-400">
              Minutes
            </label>
            <input
              type="number"
              name="minutes"
              value={@custom_minutes}
              min="1"
              max="240"
              class="w-full rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm text-slate-900 focus:border-indigo-400 focus:outline-none focus:ring-2 focus:ring-indigo-100"
            />
          </div>
          <button
            type="submit"
            class="inline-flex items-center gap-2 rounded-xl bg-gradient-to-r from-indigo-500 to-purple-600 px-4 py-2 text-sm font-semibold text-white shadow-md shadow-indigo-500/20 transition hover:from-indigo-600 hover:to-purple-700 active:scale-95"
          >
            <.icon name="hero-plus" class="h-4 w-4" />
            Start timer
          </button>
        </form>
      </div>

      <!-- Timer grid -->
      <div :if={@timers == []} class="rounded-2xl bg-white p-10 text-center shadow-sm ring-1 ring-slate-900/5">
        <.icon name="hero-clock" class="mx-auto h-14 w-14 text-slate-200" />
        <p class="mt-4 text-sm font-medium text-slate-500">No active timers</p>
        <p class="mt-1 text-xs text-slate-400">Start a preset or a custom session to get going.</p>
      </div>

      <div :if={@timers != []} class="grid gap-4 sm:grid-cols-2">
        <div
          :for={timer <- @timers}
          class={[
            "relative overflow-hidden rounded-2xl bg-white p-5 shadow-xl ring-1 transition-all",
            timer.status == :completed && "ring-indigo-200",
            timer.status == :running && "ring-emerald-200",
            timer.status == :paused && "ring-amber-200"
          ]}
        >
          <div
            class={[
              "absolute inset-x-0 top-0 h-1 transition-all duration-500",
              timer.status == :completed && "bg-indigo-500",
              timer.status == :running && "bg-emerald-500",
              timer.status == :paused && "bg-amber-400"
            ]}
            style={"width: #{progress(timer)}%"}
          />

          <div class="mb-3 flex items-start justify-between gap-3">
            <div class="min-w-0">
              <p class="truncate text-sm font-semibold text-slate-900"><%= timer.label %></p>
              <p class="mt-0.5 text-xs text-slate-400">
                <%= div(timer.duration_s, 60) %>m preset
              </p>
            </div>
            <% {label, class} = status_badge(timer.status) %>
            <span class={"rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide #{class}"}>
              <%= label %>
            </span>
          </div>

          <div class="my-5 text-center">
            <p class="font-mono text-5xl font-bold tabular-nums text-slate-900">
              <%= format_time(timer.remaining_s) %>
            </p>
          </div>

          <div class="flex items-center justify-center gap-2">
            <button
              phx-click="toggle"
              phx-value-id={timer.id}
              disabled={timer.status == :completed}
              class={[
                "inline-flex items-center gap-1 rounded-lg px-3 py-1.5 text-xs font-semibold transition",
                timer.status == :completed && "cursor-not-allowed bg-slate-100 text-slate-400",
                timer.status != :completed && "bg-white text-slate-600 ring-1 ring-slate-200 hover:bg-slate-50"
              ]}
            >
              <.icon
                name={if timer.status == :running, do: "hero-pause-solid", else: "hero-play-solid"}
                class="h-3.5 w-3.5"
              />
              <%= if timer.status == :running, do: "Pause", else: "Resume" %>
            </button>
            <button
              phx-click="reset"
              phx-value-id={timer.id}
              class="inline-flex items-center gap-1 rounded-lg bg-white px-3 py-1.5 text-xs font-semibold text-slate-600 ring-1 ring-slate-200 transition hover:bg-slate-50"
            >
              <.icon name="hero-arrow-path" class="h-3.5 w-3.5" />
              Reset
            </button>
            <button
              phx-click="stop"
              phx-value-id={timer.id}
              class="inline-flex items-center gap-1 rounded-lg bg-white px-3 py-1.5 text-xs font-semibold text-rose-600 ring-1 ring-rose-200 transition hover:bg-rose-50"
            >
              <.icon name="hero-x-mark" class="h-3.5 w-3.5" />
              Stop
            </button>
          </div>
        </div>
      </div>

      <p class="mt-6 text-center text-xs text-slate-400">
        Every timer is a <code class="rounded bg-slate-100 px-1 py-0.5">GenServer</code>
        under a <code class="rounded bg-slate-100 px-1 py-0.5">DynamicSupervisor</code>.
        Completions publish to the Notification Hub — check the inbox after one finishes.
      </p>
    </div>
    """
  end
end
