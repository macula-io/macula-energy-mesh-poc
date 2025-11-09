defmodule CortexIqProjections.CalculateMetrics.System do
  @moduledoc """
  Supervises the metrics calculation system.

  This system manages:
  - One dedicated WAMP client (for subscribing to events and publishing metrics)
  - One aggregator (subscribes to events, calculates metrics, stores and publishes)

  ## Architecture

  WAMP Client → Aggregator (subscribes to home.measured, home.connected, etc.)
                 ↓
            Calculate metrics every 1000ms
                 ↓
            Store in metrics_timeseries table
                 ↓
            Publish macula.metrics.totals_calculated

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Aggregator starts second, using the client
  - If WAMP client crashes, aggregator restarts too
  - If aggregator crashes, only aggregator restarts

  ## Metrics Published

  Performance:
  - events_per_second, measurements_per_second, meter_readings_per_second

  System Health:
  - homes_online, homes_total, homes_connected

  Energy:
  - total_production_kw, total_consumption_kw, battery totals/averages

  Market:
  - active_contracts, contract_switches_last_minute
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

    # Unique WAMP client name
    client_name = :wamp_calculate_metrics

    Logger.info("CalculateMetrics.System starting")
    Logger.info("  WAMP client: #{inspect(client_name)}")
    Logger.info("  Bondy URL: #{macula_url}")
    Logger.info("  Realm: #{realm_uri}")

    children = [
      # 1. WAMP Client - dedicated connection
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

      # 2. Aggregator - subscribes to events, calculates metrics, stores and publishes
      {CortexIqProjections.CalculateMetrics.Aggregator, [
        client: client_name
      ]}
    ]

    # rest_for_one: if WAMP crashes, aggregator restarts too
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
