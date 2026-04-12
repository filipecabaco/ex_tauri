import Config

config :pomodoro_farm, PomodoroFarmWeb.Endpoint,
  url: [host: "localhost", port: 4002, scheme: "https"],
  http: [port: 4002],
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64(),
  server: true
