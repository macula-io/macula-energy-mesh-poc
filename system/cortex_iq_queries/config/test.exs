import Config

# Configure the queries Repo for testing
config :cortex_iq_queries, CortexIqQueries.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cortexiq_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Print only warnings and errors during test
config :logger, level: :warning
