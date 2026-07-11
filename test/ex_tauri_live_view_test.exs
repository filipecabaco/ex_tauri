defmodule ExTauri.LiveViewTest do
  use ExUnit.Case, async: true

  alias ExTauri.LiveView

  # The full dispatch path (attach_hook / push_event) needs phoenix_live_view,
  # which isn't a dependency of this library — those paths are exercised in
  # host applications. Here we test the pure routing logic and the API surface.

  describe "event_key/1" do
    test "keys global shortcuts by their shortcut string" do
      params = %{"event" => "global_shortcut", "shortcut" => "CommandOrControl+K"}
      assert LiveView.event_key(params) == {:shortcut, "CommandOrControl+K"}
    end

    test "keys ordinary events by name" do
      assert LiveView.event_key(%{"event" => "tauri://drag-drop"}) == "tauri://drag-drop"
      assert LiveView.event_key(%{"event" => "my-custom-event"}) == "my-custom-event"
    end
  end

  describe "event_payload/1" do
    test "extracts the payload for ordinary events" do
      params = %{"event" => "tauri://drag-drop", "payload" => %{"paths" => ["/tmp/a.txt"]}}
      assert LiveView.event_payload(params) == %{"paths" => ["/tmp/a.txt"]}
    end

    test "passes shortcut data at the top level" do
      params = %{"event" => "global_shortcut", "shortcut" => "F11", "state" => "Pressed"}
      assert LiveView.event_payload(params) == %{"shortcut" => "F11", "state" => "Pressed"}
    end
  end

  describe "API surface" do
    setup do
      Code.ensure_loaded!(LiveView)
      :ok
    end

    test "attach and dispatch functions are defined" do
      assert function_exported?(LiveView, :attach, 1)
      assert function_exported?(LiveView, :on_mount, 4)
      assert function_exported?(LiveView, :handle_bridge_event, 3)
    end

    test "callback registration functions are defined" do
      assert function_exported?(LiveView, :put_reply, 3)
      assert function_exported?(LiveView, :put_handler, 3)
      assert function_exported?(LiveView, :delete_handler, 2)
    end

    test "using the module injects on_mount" do
      assert macro_exported?(LiveView, :__using__, 1)
    end
  end

  # A bare map stands in for the socket: the fall-through paths only read
  # socket.assigns, so no LiveView struct is needed. (Module level — defp
  # is not allowed inside describe blocks.)
  defp fake_socket, do: %{assigns: %{}}

  describe "handle_bridge_event/3 fall-through" do
    test "responses without a registered callback continue to user handlers" do
      params = %{"ref" => "123", "command" => "dialog_open", "path" => "/tmp/x"}

      assert {:cont, _socket} =
               LiveView.handle_bridge_event("tauri_response", params, fake_socket())
    end

    test "errors without a registered callback continue to user handlers" do
      params = %{"ref" => "123", "command" => "dialog_open", "error" => "denied"}
      assert {:cont, _socket} = LiveView.handle_bridge_event("tauri_error", params, fake_socket())
    end

    test "events without a registered handler continue to user handlers" do
      params = %{"event" => "tauri://drag-drop", "payload" => %{}}
      assert {:cont, _socket} = LiveView.handle_bridge_event("tauri_event", params, fake_socket())
    end

    test "unrelated events always continue" do
      assert {:cont, _socket} = LiveView.handle_bridge_event("form_submit", %{}, fake_socket())
    end
  end
end
