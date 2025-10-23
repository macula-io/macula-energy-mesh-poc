import Config

# CortexIQ Utilities - Energy provider bots
# Simulates energy providers with different pricing strategies

config :cortex_iq_utilities,
  num_providers: String.to_integer(System.get_env("NUM_PROVIDERS", "5"))

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
