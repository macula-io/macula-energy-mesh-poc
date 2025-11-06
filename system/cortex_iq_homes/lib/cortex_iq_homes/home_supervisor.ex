defmodule CortexIqHomes.HomeSupervisor do
  @moduledoc """
  Supervisor for a single home's complete vertical slice architecture.

  Supervises:
  1. HomeState (domain logic)
  2. HomeBot (coordinator - subscribes to PubSub for time ticks)
  3. Subscribe Systems (4 pooled subscribers)
  4. Publish Systems (10 pooled publishers)

  Note: SubscribeSimulationTimeAdvanced is now application-wide and broadcasts
  via PubSub instead of per-home subscriptions.

  Total per home: 1 HomeState + 1 HomeBot + 4 subscribers + 10 publishers = 16 processes
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    Supervisor.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  @impl true
  def init(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    home = Keyword.get(opts, :home)

    Logger.info("Starting HomeSupervisor for #{home_id}")
    Logger.debug("HomeSupervisor #{home_id}: Initializing supervision tree with publishers and subscribers")

    children = [
      # Business logic state (pure calculations, no WAMP)
      {CortexIqHomes.HomeState, [home_id: home_id, home: home]},

      # Thin coordinator (orchestrates subscribers → state → publishers)
      {CortexIqHomes.HomeBot, [home_id: home_id, home: home]},

      # ========================================
      # Subscriber Systems (Inbound from WAMP)
      # ========================================
      # Note: SubscribeSimulationTimeAdvanced is now a system-wide subscriber
      # that broadcasts to all homes via PubSub. See application.ex.

      # All subscribers now use shared WampPool
      {CortexIqHomes.SubscribeContractProposed.Subscriber,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.SubscribeSpotPriceUpdated.Subscriber,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.SubscribeContractConfirmed.Subscriber,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.SubscribeContractRejected.Subscriber,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      # ========================================
      # Publisher Systems (Outbound to WAMP)
      # ========================================
      # All publishers now use shared WampPool
      {CortexIqHomes.PublishHomeMeasured.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishHomeInitialized.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishHomeConnected.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishHomeDisconnected.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishContractSigned.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishContractSwitched.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishContractExpired.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishTradeExecuted.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishArbitrageProfit.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

      {CortexIqHomes.PublishBalanceUpdated.Publisher,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]}
    ]

    Logger.debug("HomeSupervisor #{home_id}: Initialized #{length(children)} children (2 state/bot + 4 subscribers + 10 publishers)")

    # Use :one_for_one strategy - if one system fails, only restart that system
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
