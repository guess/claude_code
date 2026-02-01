import Config

config :claude_code,
  cli_version: "2.1.23"

# Import environment specific config
import_config "#{config_env()}.exs"
