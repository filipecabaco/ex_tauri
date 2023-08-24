import Config

config :example_desktop, ExampleDesktopWeb.Endpoint,
  url: [host: "localhost", port: 4000, scheme: "https"],
  http: [
    port: 4000
  ],
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64(),
  server: true
