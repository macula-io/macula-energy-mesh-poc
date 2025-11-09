defmodule CortexIqProjections.CalculateCityTotals.System do
  @moduledoc """
  Supervises the complete vertical slice for calculating city-level totals.

  This system manages:
  - One dedicated WAMP client (for subscribing to home.measured events)
  - One subscriber (receives events from WAMP)
  - One aggregator (maintains city totals and publishes city.measured events)

  ## Architecture

  WAMP Client → Subscriber → Aggregator (in-memory state) → WAMP Publisher

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - Aggregator starts third, receiving events from subscriber
  - If WAMP client crashes, all restart
  - If subscriber crashes, only subscriber and aggregator restart
  - If aggregator crashes, only aggregator restarts

  ## Aggregation Logic

  - Subscribes to "be.cortexiq.home.measured" events
  - Groups by city (location field)
  - Aggregates: total_production, total_consumption, avg_battery, home_count
  - Publishes "be.cortexiq.city.measured" events every 5 seconds
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    macula_url = Keyword.get(opts, :macula_url, System.get_env("MACULA_URL", "https://localhost:9443"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("MACULA_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name for this aggregator
    client_name = :wamp_calculate_city_totals

    Logger.info("CalculateCityTotals.System starting")
    Logger.info("  WAMP client: #{inspect(client_name)}")
    Logger.info("  Bondy URL: #{macula_url}")
    Logger.info("  Realm: #{realm_uri}")

    children = [
      # 1. WAMP Client - dedicated connection for city aggregation
      %{
        id: client_name,
        start: {MaculaSdk.Wamp, :start_link, [[
          url: macula_url,
          realm: realm_uri,
          name: client_name
        ]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },

      # 2. Subscriber - subscribes to home.measured and forwards to aggregator
      {CortexIqProjections.CalculateCityTotals.Subscriber, [
        client: client_name
      ]},

      # 3. Aggregator - maintains city totals and publishes city.measured events
      {CortexIqProjections.CalculateCityTotals.Aggregator, [
        client: client_name
      ]}
    ]

    # rest_for_one: cascading restarts from top to bottom
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
