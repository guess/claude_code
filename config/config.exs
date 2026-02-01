import Config

config :claude_code,
  cli_version: "latest"

# Import environment specific config
import_config "#{config_env()}.exs"
