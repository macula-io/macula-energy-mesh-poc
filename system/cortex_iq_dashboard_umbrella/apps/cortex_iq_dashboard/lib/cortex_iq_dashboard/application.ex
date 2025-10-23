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

    children = [
      CortexIqDashboard.Repo,
      {DNSCluster, query: Application.get_env(:cortex_iq_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CortexIqDashboard.PubSub},
      {CortexIqDashboard.System, [
        realm_uri: realm_uri,
        bondy_admin_url: bondy_admin_url,
        bondy_url: bondy_url
      ]},
      # Simulation clock (configurable via ENV: SIMULATION_SPEED, SIMULATION_START_DATE)
      CortexIqDashboard.SimulationClock,
      # WAMP publisher (forwards PubSub events to WAMP)
      {CortexIqDashboard.WampPublisher, [
        realm: realm_uri,
        bondy_url: bondy_url
      ]},
      # Event aggregator (subscribes to WAMP events and writes to database)
      CortexIqDashboard.EventAggregator
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





