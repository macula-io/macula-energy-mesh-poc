import Config

# Runtime configuration for Macula Gateway Service
# Environment variables configured in Kubernetes/Docker

gateway_port = String.to_integer(System.get_env("MACULA_GATEWAY_PORT", "9443"))
realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")

config :logger, level: :info

config :macula_gateway_service,
  port: gateway_port,
  realm: realm
