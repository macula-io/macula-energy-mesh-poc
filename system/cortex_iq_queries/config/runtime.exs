import Config

# Runtime configuration for production environment
if config_env() == :prod do
  # Set logger level to :info to reduce memory usage
  config :logger, level: :info

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # Configure queries repo (read side of CQRS)
  config :cortex_iq_queries, CortexIqQueries.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6,
    # Allow app to start even if DB not immediately available
    queue_target: 5000,
    queue_interval: 1000
end
