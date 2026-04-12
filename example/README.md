# ExTauri Demo Gallery

A collection of Phoenix LiveView apps that ship as native desktop windows
via [ExTauri](https://github.com/filipecabaco/ex_tauri). Each demo is
intentionally picked to showcase something LiveView and the BEAM are
especially good at:

- **Realtime UI** without polling, thanks to `Phoenix.PubSub`.
- **Concurrent subsystems** running as independent supervised processes.
- **Fault isolation** — one misbehaving provider never takes down the rest.

Open the app with `mix ex_tauri.dev` and pick a demo from the home page.

---

## `/` — Home launcher

Landing page that lists every demo in the gallery. Plain LiveView with a
grid of cards that navigate to each sub-app.

## `/notifications` — Notification Hub

**What it is.** A unified inbox that aggregates notifications from
GitHub, Linear, Gmail and Slack into a single streaming view with
per-item actions (open, mark read, snooze, dismiss, approve, reply…).

**Why it's interesting.** Every provider is its own supervised
`GenServer`. For the demo they generate plausible-looking fake events
on a staggered interval, but the architecture is exactly what you would
use for real integrations — swap `generate/0` for an API call and
you're done. Because each source lives in its own process, a crash or
rate-limit in one provider can never take down the others: the
`Supervisor` restarts only the failing child and the rest keep
streaming.

```
ExampleDesktop.NotificationHub.Supervisor
├── NotificationHub.Store             (GenServer, broadcasts via PubSub)
├── NotificationHub.Sources.GitHub    (GenServer, ticks every 6–20s)
├── NotificationHub.Sources.Linear    (GenServer, ticks every 9–25s)
├── NotificationHub.Sources.Gmail     (GenServer, ticks every 12–30s)
└── NotificationHub.Sources.Slack     (GenServer, ticks every 5–15s)
```

Sources call `NotificationHub.Store.push/1`, the store appends to an
in-memory list and broadcasts the event on a PubSub topic. The
LiveView subscribes on mount and re-renders whenever something arrives
or changes — no polling loop, no client-side JavaScript.

**Relevant files**

- `lib/example_desktop/notification_hub.ex` — public API
- `lib/example_desktop/notification_hub/notification.ex` — normalised struct
- `lib/example_desktop/notification_hub/store.ex` — GenServer + PubSub
- `lib/example_desktop/notification_hub/source.ex` — behaviour + `__using__`
- `lib/example_desktop/notification_hub/sources/*.ex` — mock providers
- `lib/example_desktop/notification_hub/supervisor.ex` — supervision tree
- `lib/example_desktop_web/live/notification_hub_live.ex` — the LiveView

**Try it.** Kill a source in IEx and watch the inbox keep ticking:

```elixir
iex> Process.whereis(ExampleDesktop.NotificationHub.Sources.Slack) |> Process.exit(:kill)
# Supervisor restarts it a moment later — the rest of the hub is unaffected.
```

**Swapping in real providers.** Every source only has to produce a
`%Notification{}` struct. For GitHub you'd poll
`GET /notifications` and map each entry; for Linear you'd hit the
GraphQL API or wire in their webhook stream; for Gmail you'd use the
Google Pub/Sub push feed; for Slack the Events API. None of the store
or LiveView code needs to change.

## `/pomodoros` — Pomodoro Farm

**What it is.** A concurrent timer board. Fire up any number of
focus/break timers and watch them tick down in parallel. Complete a
timer and it publishes a notification to the hub so both demos are
wired together.

**Why it's interesting.** Every timer is its own `GenServer` started
under a `DynamicSupervisor`, with a `Registry` providing name-based
lookup. The LiveView never holds a reference to a timer directly — it
sends messages by id and re-renders whenever the timers broadcast
their state on PubSub. Killing one timer never affects the others.

```
ExampleDesktop.Pomodoros.Supervisor
├── Registry (unique keys, for id → pid lookup)
└── DynamicSupervisor (one_for_one)
    ├── Pomodoros.Timer #a7b3…  (GenServer)
    ├── Pomodoros.Timer #4f2c…  (GenServer)
    └── Pomodoros.Timer #9d1e…  (GenServer)
```

Each timer sends itself a `:tick` message every second while running
and broadcasts on the `"pomodoros"` PubSub topic so the LiveView can
update. When one completes it calls
`ExampleDesktop.NotificationHub.push/1` — your notification inbox fills
up without the two subsystems knowing anything about each other.

**Relevant files**

- `lib/example_desktop/pomodoros.ex` — public API
- `lib/example_desktop/pomodoros/timer.ex` — per-timer GenServer
- `lib/example_desktop/pomodoros/supervisor.ex` — registry + dynamic supervisor
- `lib/example_desktop_web/live/pomodoro_live.ex` — the LiveView

## `/notes` — Notes (classic ExTauri sample)

The original sample: a notes app persisted to SQLite via Ecto. Kept in
the gallery because it's the simplest introduction to wrapping a
LiveView as a desktop app with ExTauri.

**Relevant files**

- `lib/example_desktop/notes.ex`
- `lib/example_desktop/notes/note.ex`
- `lib/example_desktop_web/live/notes_live.ex`

---

## Running the gallery

```bash
cd example
mix setup
mix ex_tauri.dev
```

A native window opens with the home page. Click into any of the demos —
they all run inside the same Elixir release, sharing one supervision
tree and one PubSub instance.

## Ideas for more demos

The demos included were chosen for breadth, but there are plenty of
other cool things to build on ExTauri that benefit from the BEAM:

- **System/BEAM monitor.** Use `:observer_backend` to stream live
  stats from the local node into a LiveView.
- **Download manager.** Parallel downloads as `Task`s with progress
  streamed via PubSub.
- **File watcher.** `FileSystem` library + one watcher process per
  root directory.
- **Multi-agent chat.** Local LLM workers as GenServers, each with its
  own personality and memory.
- **Habit tracker.** Per-habit reminder processes that push native
  notifications via `ExTauri.Notification`.

Pull requests welcome!
