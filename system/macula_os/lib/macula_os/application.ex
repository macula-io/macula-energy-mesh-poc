defmodule MaculaOs.Application do
  @moduledoc """
  MaculaOs Application - WAMP Gateway Sidecar

  Supervision tree:
  - Metering: ETS-based usage tracking
  - Proxy.Upstream: Connection to Bondy with retry logic
  - Proxy.Server: WebSocket server on localhost
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting MaculaOs WAMP Proxy...")

    # Get configuration from environment
    port = String.to_integer(System.get_env("MACULA_PORT", "8080"))
    bondy_url = System.get_env("BONDY_URL", "ws://172.20.0.2:30080/ws")
    realm = System.get_env("BONDY_REALM") ||
      raise "BONDY_REALM environment variable is required"

    Logger.info("  Proxy listening on: localhost:#{port}")
    Logger.info("  Upstream Bondy: #{bondy_url}")
    Logger.info("  Realm: #{realm}")

    children = [
      # Metering (must start first - other components depend on it)
      {MaculaSdk.Metering, []},

      # Upstream connection to Bondy
      {MaculaOs.Proxy.Upstream, [bondy_url: bondy_url, realm: realm]},

      # WebSocket proxy server
      {MaculaOs.Proxy.Server, [port: port]}
    ]

    opts = [strategy: :one_for_one, name: MaculaOs.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
