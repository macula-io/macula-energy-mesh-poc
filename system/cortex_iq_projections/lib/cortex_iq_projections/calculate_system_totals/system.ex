defmodule CortexIqProjections.CalculateSystemTotals.System do
  @moduledoc """
  Supervises the system totals calculation.

  This system manages:
  - One dedicated WAMP client (for subscribing to home.measured and publishing totals)
  - One aggregator (subscribes to events, calculates totals, publishes results)

  ## Architecture

  WAMP Client → Aggregator (subscribes to home.measured)
                 ↓
            Calculate totals every 500ms
                 ↓
            Publish be.cortexiq.projections.totals_calculated
                 ↓
            Store in database

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Aggregator starts second, using the client
  - If WAMP client crashes, aggregator restarts too
  - If aggregator crashes, only aggregator restarts
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    bondy_url = Keyword.get(opts, :bondy_url, System.get_env("BONDY_URL", "ws://localhost:18080/ws"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("BONDY_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name
    wamp_client_name = :wamp_calculate_system_totals

    Logger.info("CalculateSystemTotals.System starting")
    Logger.info("  WAMP client: #{inspect(wamp_client_name)}")
    Logger.info("  Bondy URL: #{bondy_url}")
    Logger.info("  Realm: #{realm_uri}")

    children = [
      # 1. WAMP Client - dedicated connection
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

      # 2. Aggregator - subscribes to home.measured, calculates totals, publishes
      {CortexIqProjections.CalculateSystemTotals.Aggregator, [
        wamp_client: wamp_client_name
      ]}
    ]

    # rest_for_one: if WAMP crashes, aggregator restarts too
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
