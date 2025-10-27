import Config

# CortexIQ Homes - Home simulation bots
# Simulates homes with solar, battery, and contract optimization using
# persistent configurations from JSON files

config :cortex_iq_homes,
  homes_source: System.get_env("HOMES_SOURCE", "flanders_test_homes.json")

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
