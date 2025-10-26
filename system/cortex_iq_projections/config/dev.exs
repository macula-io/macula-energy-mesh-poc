import Config

# Configure projections database (write side of CQRS)
config :cortex_iq_projections, CortexIqProjections.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mesh_hub_dev",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 5

# Do not include metadata nor timestamps in development logs
config :logger, :default_formatter, format: "[$level] $message\n"
