import Config

case config_env() do
  :dev ->
    config :francis, dev: true

  _ ->
    config :francis, dev: false
end
