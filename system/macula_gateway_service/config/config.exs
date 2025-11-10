import Config

# Runtime configuration for Macula Gateway Service
# Production config loaded from runtime.exs

if config_env() == :prod do
  import_config "runtime.exs"
end
