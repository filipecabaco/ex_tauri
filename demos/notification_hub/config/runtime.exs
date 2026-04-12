import Config

config :notification_hub, NotificationHubWeb.Endpoint,
  url: [host: "localhost", port: 4001, scheme: "https"],
  http: [port: 4001],
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64(),
  server: true
