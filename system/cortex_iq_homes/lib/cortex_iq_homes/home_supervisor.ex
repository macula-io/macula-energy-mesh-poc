defmodule CortexIqHomes.HomeSupervisor do
  @moduledoc """
  Supervisor for a single home's complete vertical slice architecture.

  Supervises:
  1. Macula Client (single HTTP/3 QUIC connection with multiplexing)
  2. HomeState (domain logic)
  3. HomeBot (coordinator - subscribes to PubSub for time ticks)
  4. Subscribe Systems (4 subscribers)
  5. Publish Systems (10 publishers)

  Note: SubscribeSimulationTimeAdvanced is now application-wide and broadcasts
  via PubSub instead of per-home subscriptions.

  Total per home: 1 client + 1 HomeState + 1 HomeBot + 4 subscribers + 10 publishers = 17 processes

  QUIC multiplexing allows all 14 pub/sub operations to share a single connection.
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
    macula_url = Keyword.fetch!(opts, :macula_url)
    realm = Keyword.fetch!(opts, :realm)

    Logger.info("Starting HomeSupervisor for #{home_id}")
    Logger.debug("HomeSupervisor #{home_id}: Initializing supervision tree with Macula client, publishers and subscribers")

    # Generate unique client name for this home
    client_name = :"macula_client_#{home_id}"

    children = [
      # Macula HTTP/3 client (one per home, multiplexes all streams via QUIC)
      %{
        id: client_name,
        start: {MaculaSdk.Client, :start_link, [
          [
            name: client_name,
            url: macula_url,
            realm: realm
          ]
        ]}
      },

      # Business logic state (pure calculations)
      {CortexIqHomes.HomeState, [home_id: home_id, home: home]},

      # Thin coordinator (orchestrates subscribers → state → publishers)
      {CortexIqHomes.HomeBot, [home_id: home_id, home: home]},

      # ========================================
      # Subscriber Systems (Inbound from Macula)
      # ========================================
      # Note: SubscribeSimulationTimeAdvanced is now a system-wide subscriber
      # that broadcasts to all homes via PubSub. See application.ex.

      # All subscribers use this home's dedicated client
      {CortexIqHomes.SubscribeContractProposed.Subscriber,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.SubscribeSpotPriceUpdated.Subscriber,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.SubscribeContractConfirmed.Subscriber,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.SubscribeContractRejected.Subscriber,
       [home_id: home_id, client: client_name]},

      # ========================================
      # Publisher Systems (Outbound to Macula)
      # ========================================
      # All publishers use this home's dedicated client
      {CortexIqHomes.PublishHomeMeasured.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishHomeInitialized.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishHomeConnected.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishHomeDisconnected.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishContractSigned.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishContractSwitched.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishContractExpired.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishTradeExecuted.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishArbitrageProfit.Publisher,
       [home_id: home_id, client: client_name]},

      {CortexIqHomes.PublishBalanceUpdated.Publisher,
       [home_id: home_id, client: client_name]}
    ]

    Logger.debug("HomeSupervisor #{home_id}: Initialized #{length(children)} children (1 client + 2 state/bot + 4 subscribers + 10 publishers)")

    # Use :one_for_one strategy - if one system fails, only restart that system
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
