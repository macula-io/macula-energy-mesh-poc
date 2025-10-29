import Config

# Runtime configuration for production environment
if config_env() == :prod do
  # Set logger level to :info
  config :logger, level: :info

  # Prezio API configuration
  config :cortex_iq_prezio,
    api_key: System.get_env("PREZIO_API_KEY"),
    api_url: System.get_env("PREZIO_API_URL") || "https://api.prezio.com",
    poll_interval_ms: String.to_integer(System.get_env("POLL_INTERVAL_MS") || "60000")
end
