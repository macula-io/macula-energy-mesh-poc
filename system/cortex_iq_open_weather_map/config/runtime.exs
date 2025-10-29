import Config

# Runtime configuration for production environment
if config_env() == :prod do
  # Set logger level to :info
  config :logger, level: :info

  # OpenWeatherMap API configuration
  config :cortex_iq_open_weather_map,
    api_key: System.get_env("OPENWEATHERMAP_API_KEY"),
    api_url: System.get_env("OPENWEATHERMAP_API_URL") || "https://api.openweathermap.org/data/2.5",
    poll_interval_ms: String.to_integer(System.get_env("POLL_INTERVAL_MS") || "300000"),
    # Default to Brussels, Belgium coordinates
    latitude: System.get_env("LATITUDE") || "50.8503",
    longitude: System.get_env("LONGITUDE") || "4.3517"
end
