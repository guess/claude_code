import Config

config :claude_code, []

# Import environment specific config
import_config "#{config_env()}.exs"
