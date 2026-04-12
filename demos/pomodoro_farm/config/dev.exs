import Config

config :pomodoro_farm, PomodoroFarmWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-at-least-64-bytes-long-bbbbbbbbbbbbbbbbbbbb",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:default, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:default, ~w(--watch)]}
  ]

config :pomodoro_farm, PomodoroFarmWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/pomodoro_farm_web/(live|components)/.*(ex|heex)$"
    ]
  ]

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
