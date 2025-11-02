import Config

# Development configuration for CortexIQ Homes
# Connect to cluster services via PowerDNS (*.macula.local)

# ==============================================================================
# WAMP / Bondy Connection
# ==============================================================================
# Connect to Bondy hub in the KinD cluster
#
# Option 1 (Recommended): Direct NodePort access
# - Fast and reliable
# - No ingress overhead
config :cortex_iq_homes,
  bondy_url: System.get_env("BONDY_URL", "ws://172.20.0.2:30080/ws"),
  bondy_realm: System.get_env("BONDY_REALM", "be.cortexiq.energy")

# Option 2: Via nginx-ingress and PowerDNS (commented out)
# - Requires WebSocket support in ingress configuration
# - Use if you need to test through ingress layer
# config :cortex_iq_homes,
#   bondy_url: System.get_env("BONDY_URL", "ws://hub.macula.local:8080/ws"),
#   bondy_realm: System.get_env("BONDY_REALM", "be.cortexiq.energy")

# ==============================================================================
# PostgreSQL (for future use)
# ==============================================================================
# Currently cortex_iq_homes doesn't use PostgreSQL directly, but keeping
# this configuration for future event store or read model needs.
#
# PostgreSQL is exposed via ClusterIP in macula-hub namespace:
#   Service: postgres.macula-hub.svc.cluster.local
#   Port: 5432
#
# For local development, you can either:
# 1. Use port-forward: kubectl port-forward -n macula-hub svc/postgres 5432:5432
# 2. Access via LoadBalancer if configured
#
# config :cortex_iq_homes, CortexIqHomes.Repo,
#   database: "cortex_iq_dev",
#   username: "postgres",
#   password: "postgres",
#   hostname: "localhost",
#   port: 5432,
#   pool_size: 10,
#   show_sensitive_data_on_connection_error: true

# ==============================================================================
# Logger Configuration
# ==============================================================================
config :logger,
  level: :debug

# Configure the default console formatter
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :home_id]

# Enable verbose WAMP client logs for debugging (if macula_sdk supports this)
# config :macula_sdk, :wamp,
#   log_level: :debug
