# Changelog

## Unreleased

### Fixed
- **Graceful Sidecar Process Termination via Heartbeat**: Fixed an issue where pressing CMD+Q (or other app-level quit commands) would not properly terminate the sidecar process, leaving the Phoenix server running in the background. The solution uses a heartbeat mechanism where the Rust frontend continuously pings the Phoenix sidecar, and the sidecar automatically shuts down when heartbeats stop.

### Added
- **ExTauri.ShutdownManager**: New GenServer with heartbeat-based shutdown detection for Phoenix applications running as Tauri sidecars. Monitors heartbeats from the Tauri frontend and initiates graceful shutdown when they stop, ensuring proper cleanup of database connections, logs, and in-flight requests.
- **Heartbeat Endpoint**: New `/_tauri/heartbeat` endpoint for receiving health checks from the Tauri frontend.

### Technical Details

The fix implements a robust heartbeat-based shutdown mechanism:

**Heartbeat Mechanism:**
1. **Rust sends heartbeat** every 100ms to `http://localhost:4000/_tauri/heartbeat`
2. **Elixir monitors heartbeats** and checks every 100ms if a heartbeat was received
3. **Timeout detection**: If no heartbeat for 300ms (3 missed beats), shutdown is initiated
4. **Works even when**:
   - Tauri app is force-quit (CMD+Q exits too fast for signals)
   - Tauri app crashes unexpectedly
   - Process is killed without cleanup
   - Any abrupt exit scenario

**Rust Side (Tauri Frontend):**
1. Spawns async task to send HTTP GET requests every 100ms
2. Uses reqwest HTTP client with rustls for HTTPS support
3. Continues until app exits (heartbeats automatically stop on exit)
4. Keeps SIGTERM/menu handlers as backup redundancy

**Elixir Side (Phoenix Sidecar):**
1. `ExTauri.ShutdownManager` tracks last heartbeat timestamp
2. Checks every 100ms if heartbeat was received within 300ms window
3. On timeout, initiates graceful shutdown via `System.stop(0)`
4. Allows cleanup of resources (database connections, logs, etc.)
5. Ensures clean exit without orphaned processes

**Migration Guide:**

For existing ExTauri projects:

1. Add `ExTauri.ShutdownManager` to your application supervision tree in `application.ex`:

```elixir
def start(_type, _args) do
  children = [
    ExTauri.ShutdownManager,  # Add this line at the top
    # ... your other children
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

2. Add the heartbeat endpoint to your `router.ex`:

```elixir
  pipeline :api do
    plug :accepts, ["json"]
  end

  # Tauri heartbeat endpoint - no CSRF protection needed
  scope "/_tauri" do
    pipe_through :api
    get "/heartbeat", YourAppWeb.TauriController, :heartbeat
  end
```

3. Create `lib/your_app_web/controllers/tauri_controller.ex`:

```elixir
defmodule YourAppWeb.TauriController do
  use YourAppWeb, :controller

  def heartbeat(conn, _params) do
    ExTauri.ShutdownManager.heartbeat()
    json(conn, %{status: "ok"})
  end
end
```

New projects will have all of this included automatically in the generated template.
