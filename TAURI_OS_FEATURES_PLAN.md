# Tauri OS Features Integration Plan for ExTauri

## Executive Summary

This document outlines a comprehensive plan to add OS-focused Tauri features to ExTauri. The approach maintains ExTauri's architecture: **Rust handles OS integration, Unix sockets enable bidirectional communication with Elixir**.

## Current Architecture Pattern

ExTauri uses a proven Unix socket communication pattern:

```
┌─────────────────┐         Unix Socket          ┌──────────────────┐
│  Tauri (Rust)   │ ◄─────────────────────────► │  Elixir Sidecar  │
│  - OS Features  │    Command/Event Stream      │  - Business Logic│
│  - Native UI    │                              │  - Phoenix       │
└─────────────────┘                              └──────────────────┘
```

**Existing Implementation:**
- Heartbeat: Rust → Elixir (100ms interval, single byte `"h"`)
- Socket: `/tmp/tauri_heartbeat_<app_name>.sock`
- Protocol: Simple byte stream via `:gen_tcp` with `{:local, socket_path}`

## Proposed OS-Focused Features

### Tier 1: Essential Desktop Features (High Priority)

#### 1. **Notifications**
**Plugin:** `tauri-plugin-notification`

**Use Cases:**
- Background task completion alerts
- Error/warning notifications
- System status updates
- Chat/message notifications

**Rust Side:**
```rust
// Register notification capability
// Listen on socket for notification requests
// Send notification via Tauri API
// Emit click events back to Elixir
```

**Elixir Side:**
```elixir
ExTauri.Notification.show("Title", "Body", icon: :info)
ExTauri.Notification.on_click(fn notification_id ->
  # Handle notification click
end)
```

**Socket Protocol:**
- `{:notify, id, title, body, opts}` → Send notification
- `{:notification_clicked, id}` ← User clicked notification

---

#### 2. **Dialog**
**Plugin:** `tauri-plugin-dialog`

**Use Cases:**
- File picker (open/save)
- Folder selection
- Message boxes (info, warning, error, confirm)

**Rust Side:**
```rust
// Listen for dialog requests
// Show native dialog via Tauri
// Send result back to Elixir
```

**Elixir Side:**
```elixir
{:ok, path} = ExTauri.Dialog.open_file(filters: [{"Images", ["png", "jpg"]}])
{:ok, path} = ExTauri.Dialog.save_file(default_name: "export.csv")
:ok = ExTauri.Dialog.message("Operation completed!", title: "Success")
{:ok, :yes} = ExTauri.Dialog.confirm("Delete this item?")
```

**Socket Protocol:**
- `{:dialog, :open_file, id, opts}` → Show file picker
- `{:dialog_result, id, {:ok, path}}` ← File selected
- `{:dialog, :message, id, title, body, level}` → Show message
- `{:dialog_result, id, :ok}` ← Dialog closed

---

#### 3. **Clipboard**
**Plugin:** `tauri-plugin-clipboard`

**Use Cases:**
- Copy/paste text
- Copy/paste images
- Clipboard monitoring
- Rich content (HTML, RTF, files)

**Rust Side:**
```rust
// Listen for clipboard read/write requests
// Monitor clipboard changes (optional)
// Emit clipboard update events
```

**Elixir Side:**
```elixir
:ok = ExTauri.Clipboard.write_text("Hello, World!")
{:ok, text} = ExTauri.Clipboard.read_text()
{:ok, image_bytes} = ExTauri.Clipboard.read_image()
:ok = ExTauri.Clipboard.write_html("<b>Bold</b>")

ExTauri.Clipboard.on_change(fn content ->
  # React to clipboard changes
end)
```

**Socket Protocol:**
- `{:clipboard, :write_text, id, text}` → Write to clipboard
- `{:clipboard, :read_text, id}` → Read clipboard
- `{:clipboard_result, id, {:ok, text}}` ← Clipboard content
- `{:clipboard_changed, content}` ← Clipboard updated (if monitoring)

---

#### 4. **Global Shortcuts**
**Plugin:** `tauri-plugin-global-shortcut`

**Use Cases:**
- Quick actions (Cmd+Shift+Space to show window)
- Media keys (play/pause/next)
- Screenshot/screen recording triggers
- PTT (Push-to-Talk) functionality

**Rust Side:**
```rust
// Register global shortcuts
// Listen for shortcut registration requests
// Emit shortcut trigger events to Elixir
```

**Elixir Side:**
```elixir
ExTauri.GlobalShortcut.register("Cmd+Shift+K", fn ->
  # Show app window, trigger action
end)

ExTauri.GlobalShortcut.unregister("Cmd+Shift+K")
ExTauri.GlobalShortcut.unregister_all()
```

**Socket Protocol:**
- `{:shortcut, :register, id, accelerator}` → Register shortcut
- `{:shortcut_result, id, :ok}` ← Registration result
- `{:shortcut_triggered, accelerator}` ← User pressed shortcut
- `{:shortcut, :unregister, id, accelerator}` → Unregister

---

#### 5. **System Tray / Menu Bar**
**Plugin:** Built into Tauri core (`tray-icon` feature)

**Use Cases:**
- Background app with tray icon
- Quick access menu
- Status indicators
- Minimize to tray

**Rust Side:**
```rust
// Create tray icon
// Listen for menu updates
// Handle tray click events
// Update icon/tooltip dynamically
```

**Elixir Side:**
```elixir
ExTauri.Tray.create(
  icon: "/path/to/icon.png",
  tooltip: "My App",
  menu: [
    {:item, "show", "Show Window"},
    {:separator},
    {:item, "quit", "Quit"}
  ]
)

ExTauri.Tray.on_click(:show, fn ->
  # Show main window
end)

ExTauri.Tray.update_tooltip("5 new messages")
ExTauri.Tray.update_icon("/path/to/active-icon.png")
```

**Socket Protocol:**
- `{:tray, :create, id, opts}` → Create tray icon
- `{:tray, :update_menu, id, menu_items}` → Update menu
- `{:tray_clicked, menu_id}` ← User clicked menu item
- `{:tray, :update_tooltip, text}` → Update tooltip
- `{:tray, :update_icon, path}` → Update icon

---

### Tier 2: Power User Features (Medium Priority)

#### 6. **File System Access**
**Plugin:** `tauri-plugin-fs`

**Use Cases:**
- File/directory operations
- File watching
- Path utilities
- Safe file access with permissions

**Elixir Side:**
```elixir
{:ok, content} = ExTauri.FS.read_file("/path/to/file")
:ok = ExTauri.FS.write_file("/path/to/file", content)
{:ok, entries} = ExTauri.FS.read_dir("/path")
:ok = ExTauri.FS.create_dir("/path/to/new_dir")

ExTauri.FS.watch("/path/to/watch", fn event ->
  # React to file changes
end)
```

---

#### 7. **Auto-Start**
**Plugin:** `tauri-plugin-autostart`

**Use Cases:**
- Launch at login
- Background services
- System utilities

**Elixir Side:**
```elixir
:ok = ExTauri.AutoStart.enable()
:ok = ExTauri.AutoStart.disable()
{:ok, enabled?} = ExTauri.AutoStart.is_enabled()
```

---

#### 8. **Single Instance**
**Plugin:** `tauri-plugin-single-instance`

**Use Cases:**
- Prevent multiple app instances
- Focus existing window when relaunching
- Handle deep links in existing instance

**Elixir Side:**
```elixir
ExTauri.SingleInstance.on_second_instance(fn args ->
  # Handle relaunch with args
  # Focus main window
end)
```

---

#### 9. **Window State Persistence**
**Plugin:** `tauri-plugin-window-state`

**Use Cases:**
- Remember window size/position
- Restore on next launch
- Multi-monitor support

**Elixir Side:**
```elixir
# Automatic persistence
:ok = ExTauri.WindowState.enable()
```

---

#### 10. **OS Information**
**Plugin:** `tauri-plugin-os`

**Use Cases:**
- Platform detection
- System information
- Locale detection
- Theme detection (dark/light mode)

**Elixir Side:**
```elixir
{:ok, info} = ExTauri.OS.info()
# %{platform: :macos, version: "14.2", arch: "aarch64", locale: "en-US"}

{:ok, :dark} = ExTauri.OS.theme()

ExTauri.OS.on_theme_change(fn theme ->
  # React to dark/light mode changes
end)
```

---

#### 11. **Opener**
**Plugin:** `tauri-plugin-opener`

**Use Cases:**
- Open URLs in default browser
- Open files with default application
- Reveal files in Finder/Explorer

**Elixir Side:**
```elixir
:ok = ExTauri.Opener.open_url("https://example.com")
:ok = ExTauri.Opener.open_file("/path/to/file.pdf")
:ok = ExTauri.Opener.reveal_in_folder("/path/to/file.txt")
```

---

#### 12. **Window Positioner**
**Plugin:** `tauri-plugin-positioner`

**Use Cases:**
- Position window to screen corners/center
- Multi-monitor awareness
- Menubar apps

**Elixir Side:**
```elixir
:ok = ExTauri.Positioner.move_to(:center)
:ok = ExTauri.Positioner.move_to(:top_right)
:ok = ExTauri.Positioner.move_to(:tray) # Position near tray icon
```

---

### Tier 3: Advanced Features (Lower Priority)

#### 13. **Store**
**Plugin:** `tauri-plugin-store`

**Use Cases:**
- Persistent key-value storage
- Settings/preferences
- User data

**Elixir Side:**
```elixir
:ok = ExTauri.Store.set("theme", "dark")
{:ok, "dark"} = ExTauri.Store.get("theme")
:ok = ExTauri.Store.delete("theme")
{:ok, keys} = ExTauri.Store.keys()
```

---

#### 14. **Updater**
**Plugin:** `tauri-plugin-updater`

**Use Cases:**
- Auto-updates
- Update notifications
- Release channels

**Elixir Side:**
```elixir
{:ok, update} = ExTauri.Updater.check()
# %{available: true, version: "1.2.0", notes: "..."}

:ok = ExTauri.Updater.download_and_install(update)

ExTauri.Updater.on_progress(fn %{downloaded: bytes, total: total} ->
  # Show progress
end)
```

---

#### 15. **Process**
**Plugin:** `tauri-plugin-process`

**Use Cases:**
- Exit application
- Restart application
- Get PID

**Elixir Side:**
```elixir
:ok = ExTauri.Process.exit(0)
:ok = ExTauri.Process.restart()
{:ok, pid} = ExTauri.Process.pid()
```

---

#### 16. **HTTP Client** (Bonus)
**Plugin:** `tauri-plugin-http`

**Use Cases:**
- Native HTTP client (avoids CORS)
- Better performance than browser fetch
- System proxy support

**Elixir Side:**
```elixir
{:ok, response} = ExTauri.HTTP.get("https://api.example.com/data")
{:ok, response} = ExTauri.HTTP.post("https://api.example.com", body: %{...})
```

---

## Implementation Architecture

### Socket Protocol Design

**Enhanced Socket Protocol:**

```
Message Format: {:cmd, command, request_id, payload}

Commands (Rust → Elixir):
- {:event, feature, event_type, data}  # Async events
- {:response, request_id, result}      # Command responses

Commands (Elixir → Rust):
- {:request, feature, command, request_id, args}  # Sync commands
- {:listen, feature, event_type}       # Subscribe to events
- {:unlisten, feature, event_type}     # Unsubscribe
```

**Example Flow:**

```elixir
# Elixir sends notification request
socket <- {:request, :notification, :show, "req-123", %{title: "Hello", body: "World"}}

# Rust processes and responds
socket -> {:response, "req-123", {:ok, "notif-456"}}

# User clicks notification
socket -> {:event, :notification, :clicked, %{id: "notif-456"}}
```

---

### Rust Implementation Pattern

**File:** `src-tauri/src/main.rs`

```rust
use std::os::unix::net::UnixStream;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize)]
enum ElixirCommand {
    Request { feature: String, command: String, id: String, args: Value },
    Listen { feature: String, event_type: String },
    Unlisten { feature: String, event_type: String },
}

#[derive(Serialize, Deserialize)]
enum RustMessage {
    Response { id: String, result: Value },
    Event { feature: String, event_type: String, data: Value },
}

fn handle_socket_message(app: &AppHandle, msg: ElixirCommand) {
    match msg {
        ElixirCommand::Request { feature, command, id, args } => {
            match feature.as_str() {
                "notification" => handle_notification(app, command, id, args),
                "dialog" => handle_dialog(app, command, id, args),
                "clipboard" => handle_clipboard(app, command, id, args),
                // ... other features
                _ => send_error(&id, "Unknown feature"),
            }
        }
        // ... handle Listen/Unlisten
    }
}

fn handle_notification(app: &AppHandle, command: String, id: String, args: Value) {
    match command.as_str() {
        "show" => {
            let title = args["title"].as_str().unwrap();
            let body = args["body"].as_str().unwrap();

            app.notification()
                .builder()
                .title(title)
                .body(body)
                .show()
                .unwrap();

            send_response(&id, json!({"ok": true}));
        }
        _ => send_error(&id, "Unknown command"),
    }
}
```

---

### Elixir Implementation Pattern

**File:** `lib/ex_tauri/notification.ex`

```elixir
defmodule ExTauri.Notification do
  @moduledoc """
  Send system notifications from Elixir to the OS.

  ## Examples

      ExTauri.Notification.show("Build Complete", "Your project built successfully!")

      ExTauri.Notification.on_click(fn notification_id ->
        IO.puts("Notification clicked: \#{notification_id}")
      end)
  """

  use GenServer
  alias ExTauri.Socket

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def show(title, body, opts \\ []) do
    GenServer.call(__MODULE__, {:show, title, body, opts})
  end

  def on_click(callback) when is_function(callback, 1) do
    GenServer.call(__MODULE__, {:subscribe, :click, callback})
  end

  # GenServer Callbacks

  def init(_opts) do
    Socket.listen(:notification, :clicked)
    {:ok, %{callbacks: %{}}}
  end

  def handle_call({:show, title, body, opts}, _from, state) do
    request_id = generate_id()

    payload = %{
      title: title,
      body: body,
      icon: Keyword.get(opts, :icon),
      sound: Keyword.get(opts, :sound)
    }

    Socket.send_request(:notification, :show, request_id, payload)

    receive do
      {:response, ^request_id, result} -> {:reply, result, state}
    after
      5000 -> {:reply, {:error, :timeout}, state}
    end
  end

  def handle_call({:subscribe, :click, callback}, _from, state) do
    callbacks = Map.put(state.callbacks, :click, callback)
    {:reply, :ok, %{state | callbacks: callbacks}}
  end

  def handle_info({:event, :notification, :clicked, data}, state) do
    if callback = state.callbacks[:click] do
      spawn(fn -> callback.(data["id"]) end)
    end
    {:noreply, state}
  end
end
```

**File:** `lib/ex_tauri/socket.ex`

```elixir
defmodule ExTauri.Socket do
  @moduledoc """
  Enhanced Unix socket communication for Tauri features.
  Extends the heartbeat socket to support bidirectional messaging.
  """

  use GenServer

  def send_request(feature, command, request_id, args) do
    GenServer.call(__MODULE__, {:send, {:request, feature, command, request_id, args}})
  end

  def listen(feature, event_type) do
    GenServer.call(__MODULE__, {:send, {:listen, feature, event_type}})
  end

  # Encode/decode messages as JSON or Erlang Term Format (ETF)
  defp encode_message(msg) do
    Jason.encode!(msg)
  end

  defp decode_message(binary) do
    Jason.decode!(binary, keys: :atoms)
  end
end
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
**Goal:** Establish bidirectional socket protocol

1. Enhance `ExTauri.Socket` module
   - Add JSON encoding/decoding
   - Implement request/response matching
   - Add event broadcasting

2. Update Rust main.rs
   - Create message handler framework
   - Add JSON serialization
   - Set up feature routing

3. Create base behavior
   - `ExTauri.Feature` behavior for consistent API
   - Supervision tree integration
   - Error handling patterns

**Deliverable:** Working bidirectional socket with example feature

---

### Phase 2: Tier 1 Features (Week 3-6)
**Goal:** Implement essential desktop features

**Week 3:** Notifications
- `ExTauri.Notification` module
- Click handlers
- Icon/sound support

**Week 4:** Dialog
- `ExTauri.Dialog` module
- File pickers (open/save)
- Message boxes (info/error/confirm)

**Week 5:** Clipboard
- `ExTauri.Clipboard` module
- Text/image read/write
- Change monitoring

**Week 6:** Global Shortcuts
- `ExTauri.GlobalShortcut` module
- Accelerator parsing
- Platform-specific handling

---

### Phase 3: System Tray (Week 7-8)
**Goal:** Implement tray icon support

1. Tray creation and icon management
2. Dynamic menu updates
3. Click handlers
4. Status indicators

---

### Phase 4: Tier 2 Features (Week 9-12)
**Goal:** Power user features

- File system access
- Auto-start
- Single instance
- Window state persistence
- OS information
- Opener
- Window positioner

---

### Phase 5: Tier 3 Features (Week 13-16)
**Goal:** Advanced features

- Store (persistent KV)
- Updater
- Process management
- HTTP client (bonus)

---

## Mix Task Updates

### New Mix Tasks

#### `mix ex_tauri.install`
**Updates:**
```elixir
# Add feature flags to Cargo.toml based on enabled features
features = ["notification", "dialog", "clipboard", "global-shortcut"]

# Generate capabilities JSON with required permissions
permissions = [
  "notification:default",
  "dialog:default",
  "clipboard-manager:default",
  "global-shortcut:default"
]
```

#### `mix ex_tauri.features`
**New task to enable/disable features:**
```bash
mix ex_tauri.features --enable notification,dialog,clipboard
mix ex_tauri.features --disable updater
mix ex_tauri.features --list
```

---

## Configuration

### `config/config.exs`

```elixir
config :ex_tauri,
  version: "2.5.1",
  app_name: "My Desktop App",
  host: "localhost",
  port: 4000,

  # Feature configuration
  features: [
    notification: [enabled: true],
    dialog: [enabled: true],
    clipboard: [enabled: true, monitor: false],
    global_shortcut: [
      enabled: true,
      shortcuts: [
        {"Cmd+Shift+K", :show_window},
        {"Cmd+Shift+H", :toggle_visibility}
      ]
    ],
    tray: [
      enabled: true,
      icon: "priv/static/images/tray-icon.png",
      tooltip: "My App"
    ],
    auto_start: [enabled: false],
    single_instance: [enabled: true],
    updater: [enabled: true, check_on_startup: true]
  ]
```

---

## Testing Strategy

### Unit Tests
```elixir
defmodule ExTauri.NotificationTest do
  use ExUnit.Case, async: false

  test "sends notification via socket" do
    # Mock socket
    # Verify message sent
    # Verify response handled
  end

  test "handles notification click events" do
    # Register callback
    # Simulate click event from Rust
    # Verify callback invoked
  end
end
```

### Integration Tests
```elixir
defmodule ExTauri.IntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "full notification flow" do
    # Start app
    # Send notification
    # Verify OS notification shown
    # Click notification
    # Verify callback triggered
  end
end
```

---

## Documentation

### User Documentation

1. **Getting Started Guide**
   - Feature overview
   - Configuration examples
   - Common patterns

2. **API Reference**
   - Module documentation
   - Function specs
   - Usage examples

3. **Cookbook**
   - Background app with tray
   - Global shortcuts setup
   - Auto-updater configuration
   - File picker integration

### Developer Documentation

1. **Architecture Guide**
   - Socket protocol specification
   - Adding new features
   - Testing guidelines

2. **Contributing Guide**
   - Code style
   - PR process
   - Feature request template

---

## Migration Path

### Existing ExTauri Apps

**Zero Breaking Changes:**
- All new features are opt-in
- Existing heartbeat mechanism unchanged
- Backward compatible socket protocol

**Gradual Adoption:**
```elixir
# Start with notifications
config :ex_tauri, features: [notification: [enabled: true]]

# Add more features as needed
config :ex_tauri, features: [
  notification: [enabled: true],
  dialog: [enabled: true],
  global_shortcut: [enabled: true]
]
```

---

## Success Metrics

1. **Feature Completeness**
   - ✅ All Tier 1 features implemented
   - ✅ 80%+ Tier 2 features
   - ✅ 50%+ Tier 3 features

2. **Developer Experience**
   - ✅ < 5 minutes to add first notification
   - ✅ Comprehensive documentation
   - ✅ Working examples for each feature

3. **Performance**
   - ✅ < 1ms socket round-trip
   - ✅ No memory leaks
   - ✅ Graceful error handling

4. **Compatibility**
   - ✅ macOS (Intel + Apple Silicon)
   - ✅ Windows (x64)
   - ✅ Linux (x64, common DEs)

---

## Open Questions

1. **Socket Protocol Format**
   - JSON vs Erlang Term Format (ETF)?
   - JSON: Human-readable, cross-language
   - ETF: Native Erlang, faster, type-safe
   - **Recommendation:** JSON for simplicity, ETF if performance bottleneck

2. **Feature Detection**
   - How to handle platform-specific features?
   - Global shortcuts differ across OS
   - Tray icons behave differently
   - **Recommendation:** Platform checks in Elixir, graceful degradation

3. **Error Propagation**
   - How to surface Rust errors to Elixir?
   - Timeout handling for long operations
   - **Recommendation:** Standardized error tuples `{:error, :permission_denied}`

4. **Event Buffering**
   - What if Elixir can't keep up with events?
   - Clipboard monitoring could be high-volume
   - **Recommendation:** Configurable buffer size, backpressure handling

---

## Next Steps

1. **Review & Feedback**
   - Review this plan
   - Prioritize features
   - Adjust timeline

2. **Spike Implementation**
   - Build notification feature end-to-end
   - Validate socket protocol
   - Document learnings

3. **Community Input**
   - Share plan with ExTauri users
   - Gather feature requests
   - Identify edge cases

4. **Begin Phase 1**
   - Enhance socket communication
   - Set up testing infrastructure
   - Create example app

---

## References

- [Tauri Official Plugins](https://github.com/tauri-apps/plugins-workspace)
- [Tauri v2 Documentation](https://v2.tauri.app/plugin/)
- [Tauri 2.0 Stable Release](https://v2.tauri.app/blog/tauri-20/)
- [ExTauri Current Architecture](https://github.com/filipecabaco/ex_tauri)
- Current ExTauri implementation uses heartbeat pattern in `/home/user/ex_tauri/lib/ex_tauri/shutdown_manager.ex`
- Existing socket path: `/tmp/tauri_heartbeat_<app_name>.sock`

---

## Appendix: Feature Comparison Matrix

| Feature | Tier | Complexity | Platform Support | Use Case Demand |
|---------|------|------------|-----------------|-----------------|
| Notifications | 1 | Low | All | Very High |
| Dialog | 1 | Low | All | Very High |
| Clipboard | 1 | Medium | All | High |
| Global Shortcut | 1 | Medium | All | High |
| System Tray | 1 | High | All | Very High |
| File System | 2 | Medium | All | Medium |
| Auto-Start | 2 | Low | All | Medium |
| Single Instance | 2 | Low | All | Medium |
| Window State | 2 | Low | All | Medium |
| OS Info | 2 | Low | All | Medium |
| Opener | 2 | Low | All | Medium |
| Positioner | 2 | Low | All | Low |
| Store | 3 | Low | All | Low (Ecto exists) |
| Updater | 3 | High | All | Medium |
| Process | 3 | Low | All | Low |
| HTTP | 3 | Medium | All | Low (HTTPoison exists) |

**Priority Recommendation:**
1. Start with Tier 1 (Notifications, Dialog, Clipboard, Global Shortcuts, Tray)
2. Add Single Instance, Auto-Start, Window State (quick wins)
3. Add remaining features based on community feedback
