defmodule PomodoroFarmWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :pomodoro_farm

  @session_options [
    store: :cookie,
    key: "_pomodoro_farm_key",
    signing_salt: "PomSignSalt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Static,
    at: "/",
    from: :pomodoro_farm,
    gzip: false,
    only: PomodoroFarmWeb.static_paths()

  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug PomodoroFarmWeb.Router
end
