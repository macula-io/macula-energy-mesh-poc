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
      # System supervisor manages RealmManager and WampSubscriber
      {CortexIqDashboard.System, [
        realm_uri: realm_uri,
        bondy_admin_url: bondy_admin_url,
        bondy_url: bondy_url
      ]},
      # NOTE: Simulation clock removed - now runs as separate service on hub cluster
      # Vertical slice subscriber systems (each supervises WAMP client + subscriber)
      # Each needs a unique :id to avoid "more than one child specification has the id" error
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :home_initialized,
          subscriber_module: CortexIqDashboard.EventSubscribers.HomeInitializedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_home_initialized
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :home_connected,
          subscriber_module: CortexIqDashboard.EventSubscribers.HomeConnectedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_home_connected
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :home_disconnected,
          subscriber_module: CortexIqDashboard.EventSubscribers.HomeDisconnectedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_home_disconnected
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :home_measured,
          subscriber_module: CortexIqDashboard.EventSubscribers.HomeMeasuredSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_home_measured
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :home_traded,
          subscriber_module: CortexIqDashboard.EventSubscribers.HomeTradedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_home_traded
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :provider_initialized,
          subscriber_module: CortexIqDashboard.EventSubscribers.ProviderInitializedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_provider_initialized
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :contract_confirmed,
          subscriber_module: CortexIqDashboard.EventSubscribers.ContractConfirmedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_contract_confirmed
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :contract_switched,
          subscriber_module: CortexIqDashboard.EventSubscribers.ContractSwitchedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_contract_switched
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :contract_expired,
          subscriber_module: CortexIqDashboard.EventSubscribers.ContractExpiredSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_contract_expired
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :time_advanced,
          subscriber_module: CortexIqDashboard.EventSubscribers.TimeAdvancedSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_time_advanced
      ),
      Supervisor.child_spec(
        {CortexIqDashboard.SubscriberSystem, [
          event_type: :simulation_reset,
          subscriber_module: CortexIqDashboard.EventSubscribers.SimulationResetSubscriber,
          realm_uri: realm_uri,
          bondy_url: bondy_url
        ]},
        id: :subscriber_simulation_reset
      ),
      {CortexIqDashboard.SubscribeTotalsCalculated.System, [
        realm_uri: realm_uri,
        bondy_url: bondy_url
      ]},
      # Registries for entity aggregates
      {Registry, keys: :unique, name: CortexIqDashboard.HomeRegistry},
      {Registry, keys: :unique, name: CortexIqDashboard.ProviderRegistry},
      # DynamicSupervisors for entity aggregates
      {DynamicSupervisor, strategy: :one_for_one, name: CortexIqDashboard.HomeSupervisor},
      {DynamicSupervisor, strategy: :one_for_one, name: CortexIqDashboard.ProviderSupervisor},
      # Event routers (spawn entity aggregates on-demand)
      CortexIqDashboard.Aggregators.HomeStateAggregator,
      CortexIqDashboard.Aggregators.ProviderStateAggregator,
      CortexIqDashboard.Aggregators.SystemStatsAggregator,
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





