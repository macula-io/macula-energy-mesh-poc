import Config

# Configure the queries Repo for development
config :cortex_iq_queries, CortexIqQueries.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cortexiq_dashboard",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"
