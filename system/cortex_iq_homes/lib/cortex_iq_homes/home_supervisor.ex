defmodule CortexIqHomes.HomeSupervisor do
  @moduledoc """
  Supervisor for a single home's complete vertical slice architecture.

  Supervises:
  1. HomeBot (coordinator - no WAMP client)
  2. Subscribe Systems (4 with dedicated WAMP + 1 with shared pool)
  3. Publish Systems (10 outbound event slices with dedicated WAMP)

  Note: SubscribeSpotPriceUpdated uses shared WampPool (proof of concept).
  Eventually all subscribers/publishers will migrate to shared pool.

  Total per home: 1 HomeBot + 14 vertical slice systems + 1 pooled subscriber.
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
      # All subscribers now use shared WampPool
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber,
       [home_id: home_id, pool_name: CortexIqHomes.WampPool]},

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

    Logger.debug("HomeSupervisor #{home_id}: Initialized #{length(children)} children (2 state/bot + 5 subscribers + 10 publishers)")

    # Use :one_for_one strategy - if one system fails, only restart that system
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
