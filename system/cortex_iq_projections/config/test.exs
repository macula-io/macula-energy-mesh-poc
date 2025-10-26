import Config

# Configure projections database for testing
config :cortex_iq_projections, CortexIqProjections.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "mesh_hub_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# Print only warnings and errors during test
config :logger, level: :warning
