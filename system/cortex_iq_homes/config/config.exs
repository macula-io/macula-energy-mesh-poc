import Config

# CortexIQ Homes - Home simulation bots
# Simulates homes with solar, battery, and contract optimization

config :cortex_iq_homes,
  num_homes: String.to_integer(System.get_env("NUM_HOMES", "50")),
  home_id_filter: System.get_env("HOME_ID_FILTER", "all")  # Options: "all", "odd", "even"

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
