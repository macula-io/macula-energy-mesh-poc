defmodule CortexIqDashboard.SubscribeProviderMetrics.System do
  @moduledoc """
  Supervises the provider_metrics subscription vertical slice.

  This system manages:
  - One dedicated WAMP client (for subscribing to be.cortexiq.provider.metrics_calculated)
  - One subscriber (receives provider metrics, broadcasts to LiveView)

  ## Architecture

  WAMP Client → Subscriber → Phoenix.PubSub (dashboard:provider_metrics) → OverviewAggregator → LiveView

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - If WAMP client crashes, subscriber restarts too
  - If subscriber crashes, only subscriber restarts

  ## Metrics Published

  Market Summary:
  - total_active_contracts, avg_day_buy_price, most_active_provider, total_providers

  Per Provider:
  - Market position: active_contracts, market_share_percent, rank, market_share_trend
  - Financial: total_revenue, total_cost, net_profit, avg_contract_value
  - Activity: contracts_gained_last_minute, contracts_lost_last_minute, net_contract_change
  - Competitive: avg_spread, price_competitiveness
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

    Logger.info("SubscribeProviderMetrics.System starting")
    Logger.info("  Using shared WAMP pool: #{inspect(pool_name)}")

    children = [
      # Subscriber - subscribes to be.cortexiq.provider.metrics_calculated via pool
      {CortexIqDashboard.SubscribeProviderMetrics.Subscriber, [
        pool_name: pool_name
      ]}
    ]

    # one_for_one: subscriber crashes don't affect pool
    Supervisor.init(children, strategy: :one_for_one)
  end
end
