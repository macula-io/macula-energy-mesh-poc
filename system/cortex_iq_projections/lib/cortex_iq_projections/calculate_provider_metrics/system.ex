defmodule CortexIqProjections.CalculateProviderMetrics.System do
  @moduledoc """
  Supervises the provider metrics calculation system.

  This system manages:
  - One aggregator (subscribes to events via shared pool, calculates metrics, stores and publishes)

  ## Architecture

  Shared WAMP Pool → Aggregator (subscribes to contract.switched, home.traded, time_advanced)
                      ↓
                 Calculate provider metrics every 2000ms
                      ↓
                 Store in provider_states table
                      ↓
                 Publish be.cortexiq.provider.metrics_calculated

  ## Strategy

  Uses `:one_for_one` strategy:
  - Aggregator uses shared pool (no dedicated client needed)
  - If aggregator crashes, only aggregator restarts

  ## Metrics Calculated

  Market Position:
  - active_contracts, market_share_percent, rank, market_share_trend

  Financial:
  - total_revenue, total_cost, net_profit, avg_contract_value

  Activity:
  - contracts_gained_last_minute, contracts_lost_last_minute, net_contract_change

  Competitive:
  - avg_spread, price_competitiveness

  ## Event Published

  Topic: be.cortexiq.provider.metrics_calculated
  Payload: %{
    timestamp: ...,
    simulation_time: ...,
    providers: [%{provider_id, provider_name, ...all metrics...}],
    market_summary: %{...}
  }
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Use shared WAMP pool instead of dedicated client
    pool_name = Keyword.get(opts, :pool_name, CortexIqProjections.WampPool)

    Logger.info("CalculateProviderMetrics.System starting")
    Logger.info("  Using shared WAMP pool: #{inspect(pool_name)}")

    children = [
      # Aggregator - subscribes to events via pool, calculates metrics, stores and publishes
      {CortexIqProjections.CalculateProviderMetrics.Aggregator, [
        pool_name: pool_name
      ]}
    ]

    # one_for_one: aggregator crashes don't affect pool
    Supervisor.init(children, strategy: :one_for_one)
  end
end
