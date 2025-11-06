defmodule CortexIqDashboard.SubscribeProviderMetrics.Subscriber do
  @moduledoc """
  Vertical slice subscriber for provider metrics calculated events.

  Subscribes to: be.cortexiq.provider.metrics_calculated
  Broadcasts to: dashboard:provider_metrics

  ## Metrics Received

  Market Summary:
  - total_active_contracts: Total contracts across all providers
  - avg_day_buy_price: Average day buy price across providers
  - most_active_provider: Provider ID with highest market share
  - total_providers: Number of active providers

  Per Provider:
  - provider_id, provider_name, strategy
  - active_contracts, market_share_percent, rank, market_share_trend
  - day_buy_price, night_buy_price, day_sell_price, night_sell_price
  - switching_discount, minimum_monthly_kwh
  - avg_spread, price_competitiveness
  - total_revenue, total_cost, net_profit, avg_contract_value
  - contracts_gained_last_minute, contracts_lost_last_minute, net_contract_change
  - spot_buy_price, spot_sell_price
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.provider.metrics_calculated"
  @pubsub_channel "dashboard:provider_metrics"

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)

    state = %{
      pool_name: pool_name,
      subscribed: false,
      events_received: 0
    }

    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()
    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Wamp.Pool.subscribe(@topic, handler, %{}, state.pool_name) do
      :ok ->
        Logger.info("#{__MODULE__}: ✅ Subscribed to #{@topic}")
        {:noreply, %{state | subscribed: true}}
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :subscribe, 5_000)
        {:noreply, state}
    end
  rescue
    e ->
      Logger.error("#{__MODULE__}: Exception during subscribe: #{inspect(e)}, retrying in 5s...")
      Process.send_after(self(), :subscribe, 5_000)
      {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    # Extract key info for logging
    market_summary = Map.get(kwargs, "market_summary", %{})
    providers = Map.get(kwargs, "providers", [])
    total_contracts = Map.get(market_summary, "total_active_contracts", 0)
    total_providers = Map.get(market_summary, "total_providers", 0)

    events_received = state.events_received + 1

    Logger.info(
      "#{__MODULE__}: Provider metrics received (##{events_received}) - " <>
      "#{total_providers} providers, #{total_contracts} active contracts"
    )

    # Broadcast to internal PubSub for OverviewAggregator and LiveView
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:provider_metrics, kwargs}
    )

    {:noreply, %{state | events_received: events_received}}
  end
end
