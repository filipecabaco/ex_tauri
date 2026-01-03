defmodule ExampleDesktopWeb.TauriController do
  use ExampleDesktopWeb, :controller

  @doc """
  Heartbeat endpoint for Tauri frontend.
  The Rust app pings this every 100ms to signal it's still alive.
  """
  def heartbeat(conn, _params) do
    ExTauri.ShutdownManager.heartbeat()
    json(conn, %{status: "ok"})
  end
end
