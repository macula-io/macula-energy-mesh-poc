defmodule CortexIqProjections.CalculateProviderMetrics.Aggregator do
  @moduledoc """
  Calculates comprehensive provider metrics for real-time market visualization.

  Subscribes to provider/home events, tracks in-memory counters, calculates metrics
  every 2 seconds, stores in provider_states table, and publishes via WAMP.

  ## Architecture

  contract.switched + home.traded + time_advanced
  → Track events in memory
  → Calculate metrics (every 2000ms)
  → Store in provider_states table
  → Publish be.cortexiq.provider.metrics_calculated

  ## Metrics Calculated

  Market Position:
  - active_contracts: Number of active contracts per provider
  - market_share_percent: Percentage of total market
  - rank: Ranking by market share (1 = highest)
  - market_share_trend: :growing | :stable | :declining

  Financial (from home.traded events):
  - total_revenue: Cumulative revenue from selling energy to homes
  - total_cost: Cumulative cost of buying energy from homes
  - net_profit: total_revenue - total_cost
  - avg_contract_value: Revenue per active contract

  Activity (windowed):
  - contracts_gained_last_minute: New contracts in last 60 seconds
  - contracts_lost_last_minute: Lost contracts in last 60 seconds
  - net_contract_change: contracts_gained - contracts_lost

  Competitive:
  - avg_spread: Average buy-sell price spread
  - price_competitiveness: :cheapest | :competitive | :expensive
  """
  use GenServer
  require Logger
  import Ecto.Query

  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.ProviderState

  defstruct [
    :pool_name,
    :subscribed,
    # Provider tracking: %{provider_id => provider_data}
    :providers,
    # Previous market shares for trend calculation: %{provider_id => previous_percent}
    :previous_market_shares,
    # Contract activity tracking: [{timestamp_ms, :gained/:lost, provider_id}]
    :contract_activity,
    # Timing
    :last_calculation_time,
    :calc_timer,
    :current_simulation_time
  ]

  @calc_interval_ms 2_000  # Calculate metrics every 2 seconds

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)

    # Subscribe to provider/home events
    Process.send_after(self(), :subscribe_events, 2000)

    # Start periodic metrics calculation
    timer = Process.send_after(self(), :calculate_metrics, @calc_interval_ms)

    Logger.info("CalculateProviderMetrics.Aggregator started - will calculate metrics every #{@calc_interval_ms}ms")

    {:ok, %__MODULE__{
      pool_name: pool_name,
      subscribed: false,
      providers: %{},
      previous_market_shares: %{},
      contract_activity: [],
      last_calculation_time: System.monotonic_time(:millisecond),
      calc_timer: timer,
      current_simulation_time: nil
    }}
  end

  @impl true
  def handle_info(:subscribe_events, state) do
    Logger.info("#{__MODULE__}: Subscribing to provider/home events")

    subscriber_pid = self()

    # Handler functions
    contract_switched_handler = fn _topic, event_data ->
      send(subscriber_pid, {:contract_switched_event, event_data})
    end

    home_traded_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_traded_event, event_data})
    end

    time_advanced_handler = fn _topic, event_data ->
      send(subscriber_pid, {:time_advanced_event, event_data})
    end

    # Attempt all subscriptions using shared pool
    results = [
      {:contract_switched, MaculaSdk.Wamp.Pool.subscribe("be.cortexiq.market.contract.switched", contract_switched_handler, %{}, state.pool_name)},
      {:home_traded, MaculaSdk.Wamp.Pool.subscribe("be.cortexiq.home.traded", home_traded_handler, %{}, state.pool_name)},
      {:time_advanced, MaculaSdk.Wamp.Pool.subscribe("be.cortexiq.simulation.time_advanced", time_advanced_handler, %{}, state.pool_name)}
    ]

    # Check if all succeeded
    all_ok = Enum.all?(results, fn {_event, result} -> result == :ok end)

    case all_ok do
      true ->
        Logger.info("#{__MODULE__}: ✅ Successfully subscribed to all events")
        {:noreply, %{state | subscribed: true}}

      false ->
        failures = Enum.filter(results, fn {_event, result} -> result != :ok end)
        Logger.error("#{__MODULE__}: Failed to subscribe to some events: #{inspect(failures)}, retrying in 5s...")
        Process.send_after(self(), :subscribe_events, 5000)
        {:noreply, state}
    end
  rescue
    e ->
      Logger.error("#{__MODULE__}: Exception during subscribe: #{inspect(e)}, retrying in 5s...")
      Process.send_after(self(), :subscribe_events, 5000)
      {:noreply, state}
  end

  @impl true
  def handle_info({:contract_switched_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    from_provider_id = Map.get(kwargs, "from_provider_id")
    to_provider_id = Map.get(kwargs, "to_provider_id")
    now_ms = System.monotonic_time(:millisecond)

    # Track contract activity
    new_activity = state.contract_activity
    new_activity = if from_provider_id, do: [{now_ms, :lost, from_provider_id} | new_activity], else: new_activity
    new_activity = if to_provider_id, do: [{now_ms, :gained, to_provider_id} | new_activity], else: new_activity

    {:noreply, %{state | contract_activity: new_activity}}
  end

  @impl true
  def handle_info({:home_traded_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    provider_id = Map.get(kwargs, "provider_id")

    # Revenue/cost from provider perspective
    # When home imports energy, provider earns revenue (import_cost)
    # When home exports energy, provider pays cost (export_revenue)
    import_cost = Map.get(kwargs, "import_cost", 0.0) || 0.0
    export_revenue = Map.get(kwargs, "export_revenue", 0.0) || 0.0

    if provider_id do
      # Update provider revenue/cost in memory
      provider_data = Map.get(state.providers, provider_id, %{
        revenue: 0.0,
        cost: 0.0
      })

      updated_provider = %{provider_data |
        revenue: provider_data.revenue + import_cost,
        cost: provider_data.cost + export_revenue
      }

      new_providers = Map.put(state.providers, provider_id, updated_provider)
      {:noreply, %{state | providers: new_providers}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:time_advanced_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    simulation_time = Map.get(kwargs, "simulation_time")

    {:noreply, %{state |
      current_simulation_time: parse_simulation_time(simulation_time)
    }}
  end

  @impl true
  def handle_info(:calculate_metrics, state) do
    # Calculate comprehensive provider metrics
    metrics = calculate_provider_metrics(state)

    # Store in database (async)
    Task.start(fn -> store_provider_metrics(metrics) end)

    # Publish via WAMP (async)
    Task.start(fn -> publish_provider_metrics(state.pool_name, metrics) end)

    # Clean up old contract activity (older than 60 seconds)
    now_ms = System.monotonic_time(:millisecond)
    new_activity = Enum.filter(state.contract_activity, fn {timestamp_ms, _, _} ->
      now_ms - timestamp_ms < 60_000
    end)

    # Update previous market shares for next trend calculation
    new_previous_shares = metrics.providers
      |> Enum.map(fn p -> {p.provider_id, p.market_share_percent} end)
      |> Enum.into(%{})

    # Schedule next calculation
    timer = Process.send_after(self(), :calculate_metrics, @calc_interval_ms)

    {:noreply, %{state |
      contract_activity: new_activity,
      previous_market_shares: new_previous_shares,
      calc_timer: timer,
      last_calculation_time: now_ms
    }}
  end

  ## Private Functions

  defp calculate_provider_metrics(state) do
    # Load all provider data from database (read model)
    providers = Repo.all(ProviderState)

    # Calculate total active contracts for market share
    total_contracts = Enum.reduce(providers, 0, fn p, acc ->
      acc + (p.active_contracts || 0)
    end)

    # Merge in-memory financial data with database data
    providers_with_metrics = Enum.map(providers, fn provider ->
      memory_data = Map.get(state.providers, provider.provider_id, %{revenue: 0.0, cost: 0.0})

      # Calculate market share
      market_share_percent = if total_contracts > 0 do
        (provider.active_contracts || 0) / total_contracts * 100.0
      else
        0.0
      end

      # Calculate market share trend
      previous_share = Map.get(state.previous_market_shares, provider.provider_id, market_share_percent)
      market_share_trend = cond do
        market_share_percent > previous_share + 0.5 -> "growing"
        market_share_percent < previous_share - 0.5 -> "declining"
        true -> "stable"
      end

      # Calculate contract activity in last minute
      contracts_gained = count_activity(state.contract_activity, :gained, provider.provider_id)
      contracts_lost = count_activity(state.contract_activity, :lost, provider.provider_id)
      net_change = contracts_gained - contracts_lost

      # Calculate average spread
      avg_spread = if provider.day_buy_price && provider.day_sell_price do
        day_spread = provider.day_buy_price - provider.day_sell_price
        night_spread = (provider.night_buy_price || 0.0) - (provider.night_sell_price || 0.0)
        (day_spread + night_spread) / 2.0
      else
        0.0
      end

      # Calculate avg contract value
      avg_contract_value = if (provider.active_contracts || 0) > 0 do
        (provider.total_revenue || 0.0) / provider.active_contracts
      else
        0.0
      end

      %{
        provider_id: provider.provider_id,
        provider_name: provider.provider_name,
        strategy: provider.strategy,
        # Market position
        active_contracts: provider.active_contracts || 0,
        market_share_percent: Float.round(market_share_percent, 2),
        rank: 0,  # Will be calculated after sorting
        market_share_trend: market_share_trend,
        # Pricing
        day_buy_price: provider.day_buy_price,
        night_buy_price: provider.night_buy_price,
        day_sell_price: provider.day_sell_price,
        night_sell_price: provider.night_sell_price,
        switching_discount: provider.switching_discount,
        minimum_monthly_kwh: provider.minimum_monthly_kwh,
        avg_spread: Float.round(avg_spread, 4),
        price_competitiveness: "competitive",  # Will be calculated after comparison
        # Financial
        total_revenue: Float.round((provider.total_revenue || 0.0) + memory_data.revenue, 2),
        total_cost: Float.round((provider.total_cost || 0.0) + memory_data.cost, 2),
        net_profit: Float.round(((provider.total_revenue || 0.0) + memory_data.revenue) - ((provider.total_cost || 0.0) + memory_data.cost), 2),
        avg_contract_value: Float.round(avg_contract_value, 2),
        # Activity
        contracts_gained_last_minute: contracts_gained,
        contracts_lost_last_minute: contracts_lost,
        net_contract_change: net_change,
        # Spot pricing
        spot_buy_price: provider.spot_buy_price,
        spot_sell_price: provider.spot_sell_price,
        # Metadata
        last_event_at: provider.last_event_at
      }
    end)

    # Sort by market share and assign ranks
    providers_ranked = providers_with_metrics
      |> Enum.sort_by(& &1.market_share_percent, :desc)
      |> Enum.with_index(1)
      |> Enum.map(fn {provider, rank} -> Map.put(provider, :rank, rank) end)

    # Calculate price competitiveness
    avg_day_buy = if length(providers_ranked) > 0 do
      Enum.reduce(providers_ranked, 0.0, fn p, acc -> acc + (p.day_buy_price || 0.0) end) / length(providers_ranked)
    else
      0.0
    end

    providers_final = Enum.map(providers_ranked, fn provider ->
      competitiveness = cond do
        is_nil(provider.day_buy_price) -> "unknown"
        provider.day_buy_price <= avg_day_buy * 0.95 -> "cheapest"
        provider.day_buy_price >= avg_day_buy * 1.05 -> "expensive"
        true -> "competitive"
      end

      Map.put(provider, :price_competitiveness, competitiveness)
    end)

    # Calculate market summary
    market_summary = %{
      total_active_contracts: total_contracts,
      avg_day_buy_price: Float.round(avg_day_buy, 4),
      most_active_provider: List.first(providers_final) |> then(fn p -> p && p.provider_id end),
      total_providers: length(providers_final)
    }

    %{
      timestamp: DateTime.utc_now(),
      simulation_time: state.current_simulation_time,
      providers: providers_final,
      market_summary: market_summary
    }
  end

  defp count_activity(activity_list, type, provider_id) do
    Enum.count(activity_list, fn {_, activity_type, pid} ->
      activity_type == type && pid == provider_id
    end)
  end

  defp store_provider_metrics(metrics) do
    # Update each provider in the database
    Enum.each(metrics.providers, fn provider ->
      Repo.insert!(
        %ProviderState{provider_id: provider.provider_id},
        on_conflict: [
          set: [
            rank: provider.rank,
            market_share_percent: provider.market_share_percent,
            market_share_trend: provider.market_share_trend,
            total_revenue: provider.total_revenue,
            total_cost: provider.total_cost,
            net_profit: provider.net_profit,
            avg_contract_value: provider.avg_contract_value,
            contracts_gained_last_minute: provider.contracts_gained_last_minute,
            contracts_lost_last_minute: provider.contracts_lost_last_minute,
            net_contract_change: provider.net_contract_change,
            avg_spread: provider.avg_spread,
            price_competitiveness: provider.price_competitiveness,
            updated_at: DateTime.utc_now()
          ]
        ],
        conflict_target: :provider_id
      )
    end)

    Logger.debug("#{__MODULE__}: Stored provider metrics in database")
  rescue
    error ->
      Logger.error("#{__MODULE__}: Failed to store provider metrics: #{inspect(error)}")
  end

  defp publish_provider_metrics(pool_name, metrics) do
    # Convert DateTime to ISO8601 for WAMP
    payload = %{
      timestamp: DateTime.to_iso8601(metrics.timestamp),
      simulation_time: if(metrics.simulation_time, do: DateTime.to_iso8601(metrics.simulation_time), else: nil),
      providers: metrics.providers,
      market_summary: metrics.market_summary
    }

    case MaculaSdk.Wamp.Pool.publish("be.cortexiq.provider.metrics_calculated", [], payload, %{}, pool_name) do
      :ok ->
        Logger.debug("#{__MODULE__}: Published provider metrics to be.cortexiq.provider.metrics_calculated")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to publish provider metrics: #{inspect(reason)}")
    end
  end

  defp parse_simulation_time(nil), do: nil
  defp parse_simulation_time(iso8601) when is_binary(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
  defp parse_simulation_time(_), do: nil
end
