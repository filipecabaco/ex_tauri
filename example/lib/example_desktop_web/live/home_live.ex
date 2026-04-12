defmodule ExampleDesktopWeb.HomeLive do
  use ExampleDesktopWeb, :live_view

  @demos [
    %{
      slug: "notifications",
      path: "/notifications",
      name: "Notification Hub",
      tagline: "Unified inbox for GitHub, Linear, Gmail & Slack",
      description:
        "Aggregate notifications from every tool you use into a single realtime inbox. Each provider runs as its own supervised GenServer so one flaky API can't take down the others.",
      icon: "hero-bell-alert",
      gradient: "from-indigo-500 to-purple-600",
      highlights: ["Phoenix.PubSub broadcasts", "One GenServer per source", "Per-item actions"]
    },
    %{
      slug: "pomodoros",
      path: "/pomodoros",
      name: "Pomodoro Farm",
      tagline: "Run dozens of timers in parallel",
      description:
        "Each timer is its own GenServer, managed by a DynamicSupervisor and looked up through a Registry. Timers tick in real time and push a Notification Hub event when they complete.",
      icon: "hero-clock",
      gradient: "from-rose-500 to-orange-500",
      highlights: ["DynamicSupervisor", "Registry lookup", "Cross-subsystem events"]
    },
    %{
      slug: "notes",
      path: "/notes",
      name: "Notes",
      tagline: "The original ExTauri sample",
      description:
        "The classic notes app persisted to SQLite via Ecto. A good starting point for seeing how Phoenix LiveView feels wrapped as a native desktop window.",
      icon: "hero-document-text",
      gradient: "from-sky-500 to-blue-600",
      highlights: ["SQLite + Ecto", "LiveView forms", "Split pane UI"]
    }
  ]

  def mount(_params, _session, socket) do
    {:ok, assign(socket, demos: @demos, page_title: "Demos")}
  end

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-6xl">
      <div class="mb-10 text-center animate-fade-in">
        <div class="mb-4 inline-flex items-center gap-2 rounded-full bg-white/70 px-4 py-1.5 text-xs font-semibold text-indigo-600 shadow-sm ring-1 ring-slate-900/5 backdrop-blur">
          <span class="relative flex h-2 w-2">
            <span class="absolute inline-flex h-full w-full animate-ping rounded-full bg-indigo-400 opacity-75"></span>
            <span class="relative inline-flex h-2 w-2 rounded-full bg-indigo-500"></span>
          </span>
          ExTauri demo gallery
        </div>
        <h1 class="text-4xl font-extrabold tracking-tight text-slate-900 sm:text-5xl">
          Elixir desktop apps, <span class="bg-gradient-to-r from-indigo-500 to-purple-600 bg-clip-text text-transparent">alive</span>.
        </h1>
        <p class="mx-auto mt-4 max-w-2xl text-base text-slate-500">
          Every demo here ships as a native desktop window via ExTauri and leans on the things LiveView and the BEAM do best: realtime UI, concurrent processes, fault isolation and supervision.
        </p>
      </div>

      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-3">
        <.link
          :for={demo <- @demos}
          navigate={demo.path}
          class="group relative overflow-hidden rounded-2xl bg-white p-6 shadow-xl ring-1 ring-slate-900/5 transition-all duration-300 hover:-translate-y-1 hover:shadow-2xl"
        >
          <div class={[
            "absolute inset-x-0 top-0 h-1.5 bg-gradient-to-r",
            demo.gradient
          ]} />

          <div class={[
            "mb-5 inline-flex h-12 w-12 items-center justify-center rounded-xl bg-gradient-to-br shadow-lg",
            demo.gradient
          ]}>
            <.icon name={demo.icon} class="h-6 w-6 text-white" />
          </div>

          <h2 class="text-xl font-bold text-slate-900"><%= demo.name %></h2>
          <p class="mt-1 text-sm font-medium text-indigo-500"><%= demo.tagline %></p>
          <p class="mt-3 text-sm leading-relaxed text-slate-500"><%= demo.description %></p>

          <ul class="mt-5 space-y-1.5">
            <li :for={highlight <- demo.highlights} class="flex items-center gap-2 text-xs text-slate-500">
              <.icon name="hero-check-circle-solid" class="h-4 w-4 text-emerald-500" />
              <%= highlight %>
            </li>
          </ul>

          <div class="mt-6 flex items-center gap-1 text-sm font-semibold text-indigo-600 transition-all group-hover:gap-2">
            Open demo
            <.icon name="hero-arrow-right" class="h-4 w-4" />
          </div>
        </.link>
      </div>

      <div class="mt-12 rounded-2xl bg-white/60 p-6 text-sm text-slate-600 shadow-sm ring-1 ring-slate-900/5 backdrop-blur">
        <div class="flex items-start gap-3">
          <.icon name="hero-light-bulb-solid" class="mt-0.5 h-5 w-5 flex-shrink-0 text-amber-500" />
          <div>
            <p class="font-semibold text-slate-800">Why these demos?</p>
            <p class="mt-1 leading-relaxed">
              ExTauri turns Phoenix apps into real desktop binaries. These samples were picked because they <em>would be a pain to build without the BEAM</em> — keeping many moving pieces in sync, isolating failures across independent subsystems, and streaming updates to the UI without ever reaching for a polling loop.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
