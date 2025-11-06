defmodule CortexIqDashboard.SubscribeMetricsTotals.System do
  @moduledoc """
  Supervises the metrics_totals subscription vertical slice.

  This system manages:
  - One dedicated WAMP client (for subscribing to macula.metrics.totals_calculated)
  - One subscriber (receives calculated metrics, broadcasts to LiveView)

  ## Architecture

  WAMP Client → Subscriber → Phoenix.PubSub (dashboard:metrics_totals) → LiveView

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - If WAMP client crashes, subscriber restarts too
  - If subscriber crashes, only subscriber restarts

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
    # Use shared WAMP pool instead of dedicated client
    pool_name = Keyword.get(opts, :pool_name, CortexIqDashboard.WampPool)

    Logger.info("SubscribeMetricsTotals.System starting")
    Logger.info("  Using shared WAMP pool: #{inspect(pool_name)}")

    children = [
      # Subscriber - subscribes to macula.metrics.totals_calculated via pool
      {CortexIqDashboard.SubscribeMetricsTotals.Subscriber, [
        pool_name: pool_name
      ]}
    ]

    # one_for_one: subscriber crashes don't affect pool
    Supervisor.init(children, strategy: :one_for_one)
  end
end
