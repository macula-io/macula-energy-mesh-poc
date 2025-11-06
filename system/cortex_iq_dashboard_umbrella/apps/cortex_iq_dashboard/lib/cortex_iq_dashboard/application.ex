defmodule CortexIqDashboard.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    realm_uri = System.get_env("BONDY_REALM", "be.cortexiq.energy")
    bondy_admin_url = System.get_env("BONDY_ADMIN_URL", "http://localhost:18081")
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")

    # Just-in-Time (JIT) Subscription Model:
    # - NO persistent WAMP subscribers at application startup
    # - LiveViews subscribe on mount, unsubscribe on unmount
    # - This avoids overwhelming Bondy with simultaneous connections
    # - Events contain complete data needed by views (no aggregation needed)

    children = [
      {DNSCluster, query: Application.get_env(:cortex_iq_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CortexIqDashboard.PubSub},

      # System supervisor manages realm initialization only
      {CortexIqDashboard.System, [
        realm_uri: realm_uri,
        bondy_admin_url: bondy_admin_url,
        bondy_url: bondy_url
      ]}
    ]

    opts = [strategy: :one_for_one, name: CortexIqDashboard.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    Logger.warning("=" <> String.duplicate("=", 60))
    Logger.warning("CortexIqDashboard.Application.stop/1 called")
    Logger.warning("  Supervisor tree will now shutdown (children terminate in LIFO order)")
    Logger.warning("=" <> String.duplicate("=", 60))
    :ok
  end
end





