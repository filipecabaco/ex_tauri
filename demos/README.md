# ExTauri Demo Apps

Standalone Phoenix LiveView applications that ship as native desktop
windows via [ExTauri](https://github.com/filipecabaco/ex_tauri). Each
demo is its own Mix project — run any of them independently.

---

## `notification_hub/` — Unified Notification Inbox

A realtime inbox that aggregates notifications from GitHub, Linear,
Gmail and Slack. Each provider is its own supervised `GenServer`, and
the UI updates instantly via `Phoenix.PubSub`.

**Why it's interesting:**
- One `GenServer` per source — kill one in IEx and the rest keep streaming
- All state lives in a central `Store` process that broadcasts diffs
- The LiveView never polls — it subscribes and re-renders on broadcasts
- Source-scoped filter chips, unread/urgent counters, per-item actions

```
NotificationHub.Notifications.Supervisor (one_for_one)
├── Notifications.Store             GenServer + PubSub
├── Notifications.Sources.GitHub    GenServer, ticks 6–20s
├── Notifications.Sources.Linear    GenServer, ticks 9–25s
├── Notifications.Sources.Gmail     GenServer, ticks 12–30s
└── Notifications.Sources.Slack     GenServer, ticks 5–15s
```

**Swapping in real providers:** each source only needs to produce a
`%Notification{}` struct. Replace `generate/0` with an API call and
the rest of the pipeline stays the same.

### Run it

```bash
cd demos/notification_hub
mix setup
mix ex_tauri.dev    # native window
# or: mix phx.server  # browser at localhost:4001
```

---

## `pomodoro_farm/` — Concurrent Timer Board

Fire up any number of focus/break timers and watch them tick down in
parallel. Every timer is its own `GenServer` under a
`DynamicSupervisor`, found via a `Registry`.

**Why it's interesting:**
- One process per timer — true concurrency, not fake setInterval
- `DynamicSupervisor` + `Registry` for lifecycle and lookup
- Crash one timer and the rest are unaffected
- Each timer broadcasts its own tick on PubSub

```
PomodoroFarm.Pomodoros.Supervisor (one_for_one)
├── Registry (unique keys, id → pid)
└── DynamicSupervisor (one_for_one)
    ├── Pomodoros.Timer #a7b3…
    ├── Pomodoros.Timer #4f2c…
    └── Pomodoros.Timer #9d1e…
```

### Run it

```bash
cd demos/pomodoro_farm
mix setup
mix ex_tauri.dev    # native window
# or: mix phx.server  # browser at localhost:4002
```

---

## Shared assets

Both demos reference heroicons from `example/assets/vendor/heroicons`
via a symlink so icons aren't duplicated across the repo. Make sure
the `example/` directory exists when building.

## Ideas for more demos

- **System/BEAM monitor** — stream `:observer_backend` stats into a
  LiveView dashboard
- **Download manager** — parallel downloads as `Task`s with progress
  via PubSub
- **File watcher** — `FileSystem` lib + one watcher process per root
  directory, using `ExTauri.Filesystem` to read contents
- **Multi-agent chat** — local LLM workers as GenServers, each with
  its own personality and memory
- **Habit tracker** — per-habit reminder processes that push native
  notifications via `ExTauri.Notification`

Pull requests welcome!
