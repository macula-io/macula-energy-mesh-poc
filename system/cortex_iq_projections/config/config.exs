import Config

# Configure the projections Repo (write side of CQRS)
config :cortex_iq_projections,
  ecto_repos: [CortexIqProjections.Repo]

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config
import_config "#{config_env()}.exs"
