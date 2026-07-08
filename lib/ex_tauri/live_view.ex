defmodule ExTauri.LiveView do
  @moduledoc """
  Callback-style responses for Tauri commands — `use` this in your LiveViews.

  Without this module, every Tauri result arrives as a raw
  `handle_event("tauri_response", ...)` that you pattern-match by hand. With it,
  you pass a callback where you issue the command and ExTauri routes the
  response back to it:

      defmodule MyAppWeb.HomeLive do
        use MyAppWeb, :live_view
        use ExTauri.LiveView

        def handle_event("pick_file", _params, socket) do
          socket =
            ExTauri.Dialog.open(socket, [title: "Pick a file"], fn
              {:ok, %{"path" => path}}, socket -> assign(socket, :file, path)
              {:error, _reason}, socket -> put_flash(socket, :error, "No file selected")
            end)

          {:noreply, socket}
        end
      end

  `use ExTauri.LiveView` attaches a `handle_event` hook (via
  `Phoenix.LiveView.attach_hook/4`) that intercepts `"tauri_response"`,
  `"tauri_error"`, and `"tauri_event"` and dispatches them:

  - **Reply callbacks** (the optional last argument on every ExTauri API
    function) are one-shot: invoked once with `{:ok, payload}` or
    `{:error, reason}`, then removed.
  - **Event handlers** (the optional last argument to `ExTauri.Event.subscribe/3`
    and `ExTauri.GlobalShortcut.register/3`) are persistent: invoked with
    `(payload, socket)` on every occurrence until unsubscribed/unregistered.
  - Anything without a registered callback falls through to your own
    `handle_event/3` clauses, so manual handling keeps working.

  Callbacks receive the socket and must return the socket.

  If you prefer not to `use` this module (e.g. you need custom mount ordering),
  attach manually in `mount/3`:

      def mount(_params, _session, socket) do
        {:ok, ExTauri.LiveView.attach(socket)}
      end
  """

  @compile {:no_warn_undefined, Phoenix.LiveView}
  @compile {:no_warn_undefined, Phoenix.Component}

  @replies :__ex_tauri_reply_callbacks__
  @handlers :__ex_tauri_event_handlers__

  defmacro __using__(_opts) do
    quote do
      on_mount({ExTauri.LiveView, :default})
    end
  end

  @doc false
  def on_mount(:default, _params, _session, socket) do
    {:cont, attach(socket)}
  end

  @doc """
  Attaches the ExTauri response router to the socket.

  Called automatically by `use ExTauri.LiveView`; use directly when attaching
  from `mount/3` instead.
  """
  def attach(socket) do
    Phoenix.LiveView.attach_hook(
      socket,
      :ex_tauri_bridge,
      :handle_event,
      &__MODULE__.handle_bridge_event/3
    )
  end

  @doc false
  def handle_bridge_event("tauri_response", %{"ref" => ref} = params, socket) do
    pop_reply(socket, ref, {:ok, Map.drop(params, ["ref"])})
  end

  def handle_bridge_event("tauri_error", %{"ref" => ref} = params, socket) do
    pop_reply(socket, ref, {:error, params["error"]})
  end

  def handle_bridge_event("tauri_event", %{"event" => _} = params, socket) do
    key = event_key(params)

    case Map.fetch(handlers(socket), key) do
      {:ok, handler} -> {:halt, handler.(event_payload(params), socket)}
      :error -> {:cont, socket}
    end
  end

  def handle_bridge_event(_event, _params, socket), do: {:cont, socket}

  @doc false
  # Global shortcut presses are keyed per shortcut so several shortcuts can
  # have independent handlers; every other event is keyed by its name.
  def event_key(%{"event" => "global_shortcut", "shortcut" => shortcut}),
    do: {:shortcut, shortcut}

  def event_key(%{"event" => name}), do: name

  @doc false
  # Native events carry their payload under "payload"; shortcut events carry
  # their data (shortcut, state) at the top level.
  def event_payload(%{"event" => "global_shortcut"} = params),
    do: Map.drop(params, ["event"])

  def event_payload(params), do: Map.get(params, "payload")

  # ── Registration (used by ExTauri.Hook and the API modules) ────────────────

  @doc false
  def put_reply(socket, ref, fun) when is_function(fun, 2) do
    Phoenix.Component.assign(socket, @replies, Map.put(replies(socket), ref, fun))
  end

  @doc false
  def put_handler(socket, key, fun) when is_function(fun, 2) do
    Phoenix.Component.assign(socket, @handlers, Map.put(handlers(socket), key, fun))
  end

  @doc false
  def delete_handler(socket, key) do
    Phoenix.Component.assign(socket, @handlers, Map.delete(handlers(socket), key))
  end

  defp pop_reply(socket, ref, result) do
    case Map.pop(replies(socket), ref) do
      {nil, _replies} ->
        # No callback registered for this ref — let the LiveView's own
        # handle_event clauses process it.
        {:cont, socket}

      {fun, rest} ->
        socket = Phoenix.Component.assign(socket, @replies, rest)
        {:halt, fun.(result, socket)}
    end
  end

  defp replies(socket), do: Map.get(socket.assigns, @replies, %{})
  defp handlers(socket), do: Map.get(socket.assigns, @handlers, %{})
end
