defmodule ExTauri.Event do
  @moduledoc """
  Subscribe to Tauri events from your LiveView.

  Bridges to Tauri's core event system via the LiveView hook — no extra plugin
  is required. Once subscribed, every occurrence of the event is forwarded to
  your LiveView as a `"tauri_event"` event, so native happenings (file drops,
  custom Rust events, plugin events) flow into `handle_event/3` like any other
  UI event.

  ## Requirements

  - The `TauriHook` must be mounted in your LiveView (see `ExTauri.Hook`)
  - Event permissions are part of `core:default` in
    `src-tauri/capabilities/default.json` (included by `mix ex_tauri.install`;
    older projects: `mix ex_tauri.add window`)

  ## Drag and drop

  Tauri delivers file drag-and-drop as built-in events:

      def mount(_params, _session, socket) do
        socket = if connected?(socket), do: ExTauri.Event.subscribe(socket, "tauri://drag-drop"), else: socket
        {:ok, socket}
      end

      def handle_event("tauri_event", %{"event" => "tauri://drag-drop", "payload" => payload}, socket) do
        # payload["paths"] holds the dropped file paths
        {:noreply, assign(socket, :dropped, payload["paths"])}
      end

  Other built-in names: `tauri://drag-enter`, `tauri://drag-over`,
  `tauri://drag-leave`, `tauri://focus`, `tauri://blur`, `tauri://resize`,
  `tauri://move`, `tauri://theme-changed`.

  ## Custom events from Rust

  Any event emitted on the Rust side with `app.emit("my-event", payload)` can be
  subscribed to by name, giving your Rust code a direct line to LiveView.

  ## Lifecycle

  Subscriptions live on the hook element: they are cleaned up automatically
  when the user navigates away (the hook's `destroyed` callback unlistens).
  Re-subscribe in `mount/3` as shown above.
  """

  alias ExTauri.Hook

  @doc """
  Subscribes to a Tauri event by name.

  Confirmation arrives as a `"tauri_response"` event with
  `%{"command" => "event_listen", "status" => "listening"}`. Each occurrence is
  then delivered as `"tauri_event"` with `%{"event" => name, "payload" => ...}`.
  """
  def subscribe(socket, event) when is_binary(event) do
    Hook.push_command(socket, "event_listen", %{event: event})
  end

  @doc """
  Unsubscribes from a previously subscribed event.
  """
  def unsubscribe(socket, event) when is_binary(event) do
    Hook.push_command(socket, "event_unlisten", %{event: event})
  end

  @doc """
  Emits a Tauri event, delivered to Rust-side listeners registered with
  `app.listen(...)` (and any other webviews listening for it).

  ## Examples

      ExTauri.Event.emit(socket, "sync-requested", %{source: "liveview"})
  """
  def emit(socket, event, payload \\ %{}) when is_binary(event) do
    Hook.push_command(socket, "event_emit", %{event: event, payload: payload})
  end
end
