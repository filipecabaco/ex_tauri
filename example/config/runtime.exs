import Config

# Configure the database at runtime
# Use a user-writable location that works across different environments
database_path =
  System.get_env("DATABASE_PATH") ||
    Path.join([System.user_home!(), ".example_desktop", "example_desktop.db"])

# Ensure the directory exists
database_path |> Path.dirname() |> File.mkdir_p!()

config :example_desktop, ExampleDesktop.Repo,
  database: database_path,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

config :example_desktop, ExampleDesktopWeb.Endpoint,
  url: [host: "localhost", port: 4000, scheme: "https"],
  http: [
    port: 4000
  ],
  secret_key_base: :crypto.strong_rand_bytes(64) |> Base.encode64(),
  server: true
