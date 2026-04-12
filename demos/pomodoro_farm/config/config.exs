import Config

config :ex_tauri,
  version: "2.5.1",
  app_name: "Pomodoro Farm",
  host: "localhost",
  port: 4002

config :pomodoro_farm, PomodoroFarmWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: PomodoroFarmWeb.ErrorHTML, json: PomodoroFarmWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: PomodoroFarm.PubSub,
  live_view: [signing_salt: "PomSalt01"]

config :esbuild,
  version: "0.17.11",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.2.7",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
