# Changelog

## Unreleased

### Fixed
- **Graceful Sidecar Process Termination**: Fixed an issue where pressing CMD+Q (or other app-level quit commands) would not properly terminate the sidecar process, leaving the Phoenix server running in the background. The solution implements graceful shutdown on both the Rust and Elixir sides.

### Added
- **ExTauri.ShutdownManager**: New GenServer for handling graceful shutdown of Phoenix applications running as Tauri sidecars. This allows the application to properly close database connections, flush logs, and complete in-flight requests before exiting.

### Technical Details

The fix implements a two-tier graceful shutdown approach:

**Rust Side (Tauri Frontend):**
1. Captures sidecar process PID on startup for signal handling
2. On app quit (CMD+Q, window close, etc.), sends SIGTERM for graceful shutdown
3. Waits up to 2 seconds for the Phoenix process to exit gracefully
4. Falls back to SIGKILL if graceful shutdown times out
5. Handles both window close events and app-level exit events

**Elixir Side (Phoenix Sidecar):**
1. `ExTauri.ShutdownManager` GenServer traps exits and handles SIGTERM
2. When SIGTERM is received, initiates graceful application shutdown
3. Allows cleanup of resources (database connections, logs, etc.)
4. Ensures clean exit without orphaned processes

**Migration Guide:**

For existing ExTauri projects, add `ExTauri.ShutdownManager` to your application supervision tree:

```elixir
def start(_type, _args) do
  children = [
    ExTauri.ShutdownManager,  # Add this line
    # ... your other children
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

New projects will have this included automatically in the generated template.
