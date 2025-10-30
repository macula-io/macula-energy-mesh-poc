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
      {DNSCluster, query: Application.get_env(:cortex_iq_dashboard, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CortexIqDashboard.PubSub},
      # Database repo (must start before DatabaseWriter/DatabasePersister)
      CortexIqDashboard.Repo,
      # System supervisor manages RealmManager and WampSubscriber
      {CortexIqDashboard.System, [
        realm_uri: realm_uri,
        bondy_admin_url: bondy_admin_url,
        bondy_url: bondy_url
      ]},
      # NOTE: Simulation clock removed - now runs as separate service on hub cluster
      # Vertical slice subscriber systems (each supervises WAMP client + subscriber)
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_initialized,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeInitializedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_connected,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeConnectedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_disconnected,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeDisconnectedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_measured,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeMeasuredSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :home_traded,
        subscriber_module: CortexIqDashboard.EventSubscribers.HomeTradedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :provider_initialized,
        subscriber_module: CortexIqDashboard.EventSubscribers.ProviderInitializedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :contract_confirmed,
        subscriber_module: CortexIqDashboard.EventSubscribers.ContractConfirmedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :contract_switched,
        subscriber_module: CortexIqDashboard.EventSubscribers.ContractSwitchedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :contract_expired,
        subscriber_module: CortexIqDashboard.EventSubscribers.ContractExpiredSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :time_advanced,
        subscriber_module: CortexIqDashboard.EventSubscribers.TimeAdvancedSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      {CortexIqDashboard.SubscriberSystem, [
        event_type: :simulation_reset,
        subscriber_module: CortexIqDashboard.EventSubscribers.SimulationResetSubscriber,
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      # Registries for entity aggregates
      {Registry, keys: :unique, name: CortexIqDashboard.HomeRegistry},
      {Registry, keys: :unique, name: CortexIqDashboard.ProviderRegistry},
      # DynamicSupervisors for entity aggregates
      {DynamicSupervisor, strategy: :one_for_one, name: CortexIqDashboard.HomeSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: CortexIqDashboard.ProviderSupervisor},
      # Database I/O worker (async writes for aggregate state, no business logic)
      CortexIqDashboard.DatabaseWriter,
      # Flow-based time-series writer (high-throughput event logging with back-pressure)
      CortexIqDashboard.DatabaseWriter.Pipeline,
      # Event routers (spawn entity aggregates on-demand)
      CortexIqDashboard.Aggregators.HomeStateAggregator,
      CortexIqDashboard.Aggregators.ProviderStateAggregator,
      CortexIqDashboard.Aggregators.SystemStatsAggregator,
      # Database persistence (listens to entity state changes and persists to DB)
      CortexIqDashboard.DatabasePersister,
      # Market components (calculate and broadcast spot prices)
      CortexIqDashboard.Market.SpotMarketBroadcaster,
      # View aggregators (maintain derived views in-memory, push updates to LiveView)
      CortexIqDashboard.Views.OverviewAggregator,
      CortexIqDashboard.Views.HomesViewAggregator,
      CortexIqDashboard.Views.ProvidersViewAggregator
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





