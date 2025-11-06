defmodule CortexIqDashboard.Views.OverviewAggregator do
  @moduledoc """
  Maintains the Overview view state in-memory.

  Subscribes to entity state changes and aggregates:
  - Total homes active
  - Total providers active
  - Total energy traded (kWh)
  - Total contract switches
  - Total savings ($)
  - System-wide production/consumption
  """
  use GenServer
  require Logger

  defstruct [
    providers: %{},  # %{provider_id => provider_state} for aggregation
    total_contract_switches: 0,
    total_savings: 0.0,
    total_arbitrage_profit: 0.0,  # Sum of all home arbitrage profits
    # CortexIQ financial tracking
    cortexiq_total_commission: 0.0,
    cortexiq_total_savings: 0.0,
    cortexiq_net_savings: 0.0,
    savings_history: [],  # Last 100 savings events for charting
    current_spot_price: nil,
    spot_price_history: [],  # Last 50 spot prices for charting
    simulation_time: nil,
    simulation_speed: nil,
    simulation_paused: false,
    # Pre-calculated aggregates from projections service (received via WAMP)
    total_homes: 0,
    connected_homes_count: 0,  # Homes with connected_at set and disconnected_at nil
    total_production_kw: 0.0,
    total_consumption_kw: 0.0,
    avg_battery_percent: 0.0,
    total_energy_bought_kwh: 0.0,
    total_energy_sold_kwh: 0.0,
    total_cost_paid: 0.0,
    total_revenue_received: 0.0,
    last_updated_at: nil,
    has_data: false  # Track if we've received provider metrics events
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Subscribe to PubSub channels
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:provider")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "market:spot")

    # Subscribe to pre-calculated totals from projections service
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:totals_calculated")

    # Subscribe to provider metrics from projections service (event-driven)
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:provider_metrics")

    # Subscribe to simulation events
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:contract_event")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")

    Logger.info("OverviewAggregator: Started and subscribed to PubSub channels (event-driven, no RPC)")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Return pre-calculated aggregates from state (received from projections service)
    total_providers = map_size(state.providers)

    overview = %{
      total_homes: state.total_homes,  # From projections service
      connected_homes_count: state.connected_homes_count,  # Connected homes
      total_providers: total_providers,
      total_energy_traded_kwh: state.total_energy_bought_kwh + state.total_energy_sold_kwh,
      total_contract_switches: state.total_contract_switches,
      total_savings: state.total_savings,
      total_arbitrage_profit: state.total_arbitrage_profit,
      # CortexIQ financial metrics (from individual homes, sum calculated on event)
      cortexiq_total_commission: state.cortexiq_total_commission,
      cortexiq_total_savings: state.cortexiq_total_savings,
      cortexiq_net_savings: state.cortexiq_net_savings,
      savings_history: state.savings_history,
      current_spot_price: state.current_spot_price,
      spot_price_history: state.spot_price_history,
      # Pre-calculated aggregates (received from projections service)
      total_production_kw: state.total_production_kw,
      total_consumption_kw: state.total_consumption_kw,
      avg_battery_percent: state.avg_battery_percent,
      total_energy_bought_kwh: state.total_energy_bought_kwh,
      total_energy_sold_kwh: state.total_energy_sold_kwh,
      total_cost_paid: state.total_cost_paid,
      total_revenue_received: state.total_revenue_received,
      simulation_time: state.simulation_time,
      simulation_speed: state.simulation_speed,
      simulation_paused: state.simulation_paused,
      last_updated_at: state.last_updated_at,
      has_data: state.has_data  # Track if we've received provider metrics
    }

    {:reply, overview, state}
  end

  @impl true
  def handle_info({:reset_simulation}, state) do
    Logger.info("OverviewAggregator: Resetting - clearing all state")

    # Reset to initial state (event-driven, no RPC calls)
    new_state = %__MODULE__{}

    # Broadcast empty state to UI immediately
    broadcast_view_updated()

    Logger.info("OverviewAggregator: Reset complete, waiting for events...")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:totals_calculated, totals}, state) do
    # Receive pre-calculated totals from projections service (via dashboard:totals_calculated)
    total_homes = Map.get(totals, "total_homes", 0)  # All initialized homes (from database)
    connected_homes_count = Map.get(totals, "connected_homes_count", 0)  # Currently active homes
    total_production_kw = Map.get(totals, "total_production_kw", 0.0)
    total_consumption_kw = Map.get(totals, "total_consumption_kw", 0.0)
    avg_battery_percent = Map.get(totals, "avg_battery_percent", 0.0)

    Logger.info("OverviewAggregator: Received totals - connected=#{connected_homes_count}, total=#{total_homes}, prod=#{Float.round(total_production_kw, 1)}kW, cons=#{Float.round(total_consumption_kw, 1)}kW, battery=#{Float.round(avg_battery_percent, 1)}%")

    new_state = %{state |
      total_homes: total_homes,  # All initialized homes
      connected_homes_count: connected_homes_count,  # Currently active homes
      total_production_kw: total_production_kw,
      total_consumption_kw: total_consumption_kw,
      avg_battery_percent: avg_battery_percent,
      last_updated_at: DateTime.utc_now()
    }

    # Broadcast immediately - no need for throttling since projections already throttles (500ms)
    broadcast_view_updated()

    {:noreply, new_state}
  end

  # NOTE: Removed home_state_changed handler - we now get totals from projections service
  # Individual home states are no longer tracked here

  @impl true
  def handle_info({:provider_state_changed, provider_id, provider_state}, state) do
    new_providers = Map.put(state.providers, provider_id, provider_state)
    new_state = %{state | providers: new_providers, last_updated_at: DateTime.utc_now()}

    # Broadcast immediately
    broadcast_view_updated()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:spot_price_updated, spot_data}, state) do
    # Market spot price updated
    spot_price = spot_data.spot_price

    # Add to history (keep last 50)
    new_history = [%{
      price: spot_price,
      timestamp: DateTime.utc_now(),
      production_kw: spot_data.total_production_kw,
      consumption_kw: spot_data.total_consumption_kw
    } | state.spot_price_history]
    |> Enum.take(50)

    new_state = %{state |
      current_spot_price: spot_price,
      spot_price_history: new_history,
      last_updated_at: DateTime.utc_now()
    }

    # Broadcast immediately
    broadcast_view_updated()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:time_advanced, kwargs}, state) do
    simulation_time = parse_simulation_time(kwargs)
    simulation_speed = Map.get(kwargs, "speed")
    simulation_paused = Map.get(kwargs, "paused", false)

    new_state = %{state |
      simulation_time: simulation_time,
      simulation_speed: simulation_speed,
      simulation_paused: simulation_paused,
      last_updated_at: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:contract_event, :switched, kwargs}, state) do
    new_state = %{state |
      total_contract_switches: state.total_contract_switches + 1,
      total_savings: state.total_savings + Map.get(kwargs, "projected_savings", 0.0),
      last_updated_at: DateTime.utc_now()
    }

    {:noreply, new_state}
  end

  # Ignore other contract event types
  @impl true
  def handle_info({:contract_event, _type, _kwargs}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:provider_metrics, kwargs}, state) do
    # Receive provider metrics from projections service (event-driven)
    market_summary = Map.get(kwargs, "market_summary", %{})
    providers = Map.get(kwargs, "providers", [])
    total_contracts = Map.get(market_summary, "total_active_contracts", 0)
    total_providers = Map.get(market_summary, "total_providers", 0)

    Logger.info(
      "OverviewAggregator: Received provider metrics - " <>
      "#{total_providers} providers, #{total_contracts} active contracts"
    )

    # Convert provider list to map for easier lookup
    providers_map = Enum.reduce(providers, %{}, fn provider, acc ->
      provider_id = Map.get(provider, "provider_id")
      if provider_id do
        Map.put(acc, provider_id, provider)
      else
        acc
      end
    end)

    new_state = %{state |
      providers: providers_map,
      has_data: true,
      last_updated_at: DateTime.utc_now()
    }

    # Broadcast to UI
    broadcast_view_updated()

    {:noreply, new_state}
  end

  # NOTE: Removed home_connected/disconnected handlers
  # Total homes count now comes from projections service via totals_calculated

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp broadcast_view_updated do
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "view:overview",
      :view_updated
    )
  end

  defp parse_simulation_time(kwargs) do
    case Map.get(kwargs, "simulation_time") do
      time when is_binary(time) ->
        case DateTime.from_iso8601(time) do
          {:ok, dt, _offset} -> dt
          _ -> nil
        end
      _ -> nil
    end
  end
end
