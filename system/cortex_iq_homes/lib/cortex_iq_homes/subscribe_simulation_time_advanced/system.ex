defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.System do
  @moduledoc """
  Supervises the simulation.time_advanced subscription vertical slice.

  This system manages:
  - One dedicated Macula client (for subscribing to simulation.time_advanced)
  - One subscriber (receives time ticks, broadcasts to ALL homes via PubSub)

  ## Architecture

  Macula Client → Subscriber → PubSub ("homes:simulation_time_tick") → HomeBots

  ## Strategy

  Uses `:rest_for_one` strategy:
  - Macula client starts first
  - Subscriber starts second, using the client
  - If Macula client crashes, subscriber restarts too
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

    macula_url = Keyword.get(opts, :macula_url, Application.get_env(:cortex_iq_homes, :macula_url, "https://localhost:9443"))
    realm = Keyword.get(opts, :realm, Application.get_env(:cortex_iq_homes, :macula_realm, "be.cortexiq.energy"))

    client_name = :macula_subscribe_simulation_time_advanced

    Logger.info("📝 Creating dedicated Macula client: #{client_name}")
    Logger.info("  macula_url: #{macula_url}")
    Logger.info("  realm: #{realm}")

    children = [
      # Dedicated Macula client for simulation time subscriptions
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

      # Subscriber - subscribes to be.cortexiq.simulation.time_advanced via dedicated client
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber, [
        client: client_name
      ]}
    ]

    Logger.info("🚀 SubscribeSimulationTimeAdvanced.System initializing #{length(children)} children...")

    # Use rest_for_one: if Macula client crashes, subscriber restarts too
    result = Supervisor.init(children, strategy: :rest_for_one)
    Logger.info("✅ SubscribeSimulationTimeAdvanced.System init completed: #{inspect(result)}")
    result
  end
end
