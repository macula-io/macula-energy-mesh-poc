defmodule CortexIqProjections.CalculateProviderMetrics.System do
  @moduledoc """
  Supervises the provider metrics calculation system.

  This system manages:
  - One aggregator (subscribes to events via shared client, calculates metrics, stores and publishes)

  ## Architecture

  Shared Macula Client → Aggregator (subscribes to contract.switched, home.traded, time_advanced)
                          ↓
                     Calculate provider metrics every 2000ms
                          ↓
                     Store in provider_states table
                          ↓
                     Publish be.cortexiq.provider.metrics_calculated

  ## Strategy

  Uses `:one_for_one` strategy:
  - Aggregator uses shared client (QUIC multiplexing handles all subscriptions)
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
    # Use shared Macula client (QUIC multiplexing replaces pool)
    client = Keyword.get(opts, :client, CortexIqProjections.MaculaClient)

    Logger.info("CalculateProviderMetrics.System starting")
    Logger.info("  Using shared Macula client: #{inspect(client)}")

    children = [
      # Aggregator - subscribes to events via shared client, calculates metrics, stores and publishes
      {CortexIqProjections.CalculateProviderMetrics.Aggregator, [
        client: client
      ]}
    ]

    # one_for_one: aggregator crashes don't affect client
    Supervisor.init(children, strategy: :one_for_one)
  end
end
