defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.System do
  @moduledoc """
  Supervises the simulation.time_advanced subscription vertical slice.

  This system manages:
  - One dedicated WAMP client (for subscribing to simulation.time_advanced)
  - One subscriber (receives time ticks, broadcasts to ALL homes via PubSub)

  ## Architecture

  WAMP Client → Subscriber → PubSub ("homes:simulation_time_tick") → HomeBots

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - If WAMP client crashes, subscriber restarts too
  - If subscriber crashes, only subscriber restarts
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("🟢 SubscribeSimulationTimeAdvanced.System.init called")

    bondy_url = Keyword.get(opts, :bondy_url, System.get_env("BONDY_URL", "ws://localhost:18080/ws"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("BONDY_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name for this subscription
    wamp_client_name = :wamp_subscribe_simulation_time_advanced

    Logger.info("📝 SubscribeSimulationTimeAdvanced.System configuration:")
    Logger.info("  WAMP client: #{inspect(wamp_client_name)}")
    Logger.info("  Bondy URL: #{bondy_url}")
    Logger.info("  Realm: #{realm_uri}")
    Logger.info("  Strategy: :rest_for_one")

    children = [
      # 1. WAMP Client - dedicated connection for simulation time events
      %{
        id: wamp_client_name,
        start: {MaculaSdk.Wamp, :start_link, [[
          url: bondy_url,
          realm: realm_uri,
          name: wamp_client_name
        ]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },

      # 2. Subscriber - subscribes to be.cortexiq.simulation.time_advanced
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber, [
        wamp_client: wamp_client_name
      ]}
    ]

    Logger.info("🚀 SubscribeSimulationTimeAdvanced.System initializing #{length(children)} children...")

    # rest_for_one: if WAMP crashes, subscriber restarts too
    result = Supervisor.init(children, strategy: :rest_for_one)
    Logger.info("✅ SubscribeSimulationTimeAdvanced.System init completed: #{inspect(result)}")
    result
  end
end
