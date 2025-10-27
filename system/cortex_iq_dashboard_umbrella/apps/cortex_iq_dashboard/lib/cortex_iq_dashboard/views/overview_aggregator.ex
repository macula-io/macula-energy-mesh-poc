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
    homes: %{},  # %{home_id => home_state} for aggregation
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
    last_updated_at: nil,
    broadcast_timer: nil,  # Timer ref for throttling broadcasts
    pending_broadcast: false  # Flag indicating broadcast is scheduled
  ]

  @broadcast_interval_ms 500  # Throttle broadcasts to max 2x per second

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
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:home")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:provider")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "market:spot")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")

    Logger.info("OverviewAggregator: Started and subscribed to dashboard control")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    # Calculate aggregated metrics from entity states
    total_homes = map_size(state.homes)
    total_providers = map_size(state.providers)

    # Aggregate home metrics
    {total_production_kw, total_consumption_kw, total_battery_percent, total_energy_bought_kwh, total_energy_sold_kwh, total_cost_paid, total_revenue_received, cortexiq_commission, cortexiq_savings, cortexiq_net} =
      state.homes
      |> Map.values()
      |> Enum.reduce({0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0}, fn home, {prod, cons, batt, bought, sold, cost, rev, comm, sav, net} ->
        {
          prod + (home.production_kw || 0.0),
          cons + (home.consumption_kw || 0.0),
          batt + (home.state_of_charge_pct || 0.0),
          bought + (home.energy_bought_kwh || 0.0),
          sold + (home.energy_sold_kwh || 0.0),
          cost + (home.cost_paid || 0.0),
          rev + (home.revenue_received || 0.0),
          comm + (home.cortexiq_total_commission || 0.0),
          sav + (home.cortexiq_total_savings || 0.0),
          net + (home.cortexiq_net_savings || 0.0)
        }
      end)

    avg_battery_percent =
      if total_homes > 0, do: total_battery_percent / total_homes, else: 0.0

    overview = %{
      total_homes: total_homes,
      total_providers: total_providers,
      total_energy_traded_kwh: total_energy_bought_kwh + total_energy_sold_kwh,
      total_contract_switches: state.total_contract_switches,
      total_savings: state.total_savings,
      total_arbitrage_profit: state.total_arbitrage_profit,
      # CortexIQ financial metrics
      cortexiq_total_commission: cortexiq_commission,
      cortexiq_total_savings: cortexiq_savings,
      cortexiq_net_savings: cortexiq_net,
      savings_history: state.savings_history,
      current_spot_price: state.current_spot_price,
      spot_price_history: state.spot_price_history,
      total_production_kw: total_production_kw,
      total_consumption_kw: total_consumption_kw,
      avg_battery_percent: avg_battery_percent,
      total_energy_bought_kwh: total_energy_bought_kwh,
      total_energy_sold_kwh: total_energy_sold_kwh,
      total_cost_paid: total_cost_paid,
      total_revenue_received: total_revenue_received,
      simulation_time: state.simulation_time,
      simulation_speed: state.simulation_speed,
      simulation_paused: state.simulation_paused,
      last_updated_at: state.last_updated_at
    }

    {:reply, overview, state}
  end

  @impl true
  def handle_info({:reset_simulation}, _state) do
    Logger.info("OverviewAggregator: Resetting - clearing all state")

    # Reset to initial state
    new_state = %__MODULE__{}

    # Broadcast empty state to UI
    broadcast_view_updated()

    Logger.info("OverviewAggregator: Reset complete")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    Logger.info("OverviewAggregator received home state: #{home_id} prod=#{home_state.production_kw}kW cons=#{home_state.consumption_kw}kW")
    new_homes = Map.put(state.homes, home_id, home_state)
    new_state = %{state | homes: new_homes, last_updated_at: DateTime.utc_now()}

    # Schedule throttled broadcast
    {:noreply, schedule_broadcast(new_state)}
  end

  @impl true
  def handle_info({:provider_state_changed, provider_id, provider_state}, state) do
    new_providers = Map.put(state.providers, provider_id, provider_state)
    new_state = %{state | providers: new_providers, last_updated_at: DateTime.utc_now()}

    # Schedule throttled broadcast
    {:noreply, schedule_broadcast(new_state)}
  end

  @impl true
  def handle_info(:broadcast_now, state) do
    # Timer fired, actually send the broadcast
    Logger.debug("OverviewAggregator: Broadcasting view update (throttled)")
    broadcast_view_updated()
    {:noreply, %{state | broadcast_timer: nil, pending_broadcast: false}}
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

    {:noreply, schedule_broadcast(new_state)}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, state) do
    topic = get_in(event_data, [:details, "topic"]) || "unknown"
    kwargs = event_data[:kwargs] || %{}

    new_state = cond do
      String.contains?(topic, "simulation.time") ->
        simulation_time = parse_simulation_time(kwargs)
        simulation_speed = Map.get(kwargs, "speed")
        simulation_paused = Map.get(kwargs, "paused", false)
        %{state |
          simulation_time: simulation_time,
          simulation_speed: simulation_speed,
          simulation_paused: simulation_paused,
          last_updated_at: DateTime.utc_now()
        }

      String.contains?(topic, "savings_realized") ->
        # Track cumulative savings over time for charting
        gross_savings = Map.get(kwargs, "gross_savings", 0.0)
        commission = Map.get(kwargs, "cortexiq_commission", 0.0)
        net_savings = Map.get(kwargs, "net_savings_to_customer", 0.0)
        cumulative_commission = Map.get(kwargs, "cumulative_commission", commission)
        cumulative_savings = Map.get(kwargs, "cumulative_gross_savings", gross_savings)
        cumulative_net = Map.get(kwargs, "cumulative_net_savings", net_savings)

        # Add to savings history (keep last 100 points)
        new_history = [%{
          timestamp: DateTime.utc_now(),
          simulation_time: state.simulation_time,
          gross_savings: cumulative_savings,
          commission: cumulative_commission,
          net_savings: cumulative_net
        } | state.savings_history]
        |> Enum.take(100)

        %{state |
          savings_history: new_history,
          last_updated_at: DateTime.utc_now()
        }

      String.contains?(topic, "contract.switched") ->
        %{state |
          total_contract_switches: state.total_contract_switches + 1,
          total_savings: state.total_savings + Map.get(kwargs, "projected_savings", 0.0),
          last_updated_at: DateTime.utc_now()
        }

      String.contains?(topic, "arbitrage_profit") ->
        # Home published arbitrage profit event
        profit = Map.get(kwargs, "profit", 0.0)
        %{state |
          total_arbitrage_profit: state.total_arbitrage_profit + profit,
          last_updated_at: DateTime.utc_now()
        }

      true ->
        state
    end

    {:noreply, new_state}
  end

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

  defp schedule_broadcast(state) do
    if state.pending_broadcast do
      # Broadcast already scheduled, don't schedule another
      state
    else
      # Schedule a broadcast after interval
      timer_ref = Process.send_after(self(), :broadcast_now, @broadcast_interval_ms)
      %{state | broadcast_timer: timer_ref, pending_broadcast: true}
    end
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
