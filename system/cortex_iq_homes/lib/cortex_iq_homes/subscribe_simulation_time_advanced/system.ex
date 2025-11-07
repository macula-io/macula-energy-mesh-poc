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

    bondy_url = Keyword.get(opts, :bondy_url, Application.get_env(:cortex_iq_homes, :bondy_url, "ws://localhost:18080/ws"))
    realm = Keyword.get(opts, :realm, Application.get_env(:cortex_iq_homes, :bondy_realm, "be.cortexiq.energy"))

    wamp_client_name = :wamp_subscribe_simulation_time_advanced

    Logger.info("📝 Creating dedicated WAMP client: #{wamp_client_name}")
    Logger.info("  bondy_url: #{bondy_url}")
    Logger.info("  realm: #{realm}")

    children = [
      # Dedicated WAMP client for simulation time subscriptions
      # This avoids potential Pool API issues and matches projections' architecture
      %{
        id: wamp_client_name,
        start: {MaculaSdk.Wamp.Client, :start_link, [
          [
            name: wamp_client_name,
            url: bondy_url,
            realm: realm
          ]
        ]}
      },

      # Subscriber - subscribes to be.cortexiq.simulation.time_advanced via dedicated client
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber, [
        wamp_client: wamp_client_name
      ]}
    ]

    Logger.info("🚀 SubscribeSimulationTimeAdvanced.System initializing #{length(children)} children...")

    # Use rest_for_one: if WAMP client crashes, subscriber restarts too
    result = Supervisor.init(children, strategy: :rest_for_one)
    Logger.info("✅ SubscribeSimulationTimeAdvanced.System init completed: #{inspect(result)}")
    result
  end
end
