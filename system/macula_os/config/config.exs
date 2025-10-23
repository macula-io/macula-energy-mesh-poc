import Config

# MaculaOs - Distributed runtime for BEAM applications
# Configuration for WAMP realm connectivity

config :macula_os,
  realm: [
    uri: "be.cortexiq.energy",
    hub_url: System.get_env("BONDY_URL", "ws://localhost:18080/ws")
  ]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
