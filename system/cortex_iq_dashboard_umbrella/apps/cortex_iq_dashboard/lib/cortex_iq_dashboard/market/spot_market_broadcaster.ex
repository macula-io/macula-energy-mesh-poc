defmodule CortexIqDashboard.Market.SpotMarketBroadcaster do
  @moduledoc """
  Calculates and broadcasts spot market prices to the energy realm.

  Aggregates production and consumption from all homes, calculates
  spot price using supply/demand formula, and publishes via WAMP.

  Broadcast frequency: Every 10 simulation-minutes or on significant price change (>5%)
  """
  use GenServer
  require Logger

  @broadcast_interval_ms 10_000  # 10 seconds real-time (~29 simulation hours at 105120x)
  @significant_change_threshold 0.05  # 5% price change triggers immediate broadcast

  defstruct [
    homes: %{},  # %{home_id => %{production_kw, consumption_kw}}
    last_spot_price: nil,
    last_broadcast_at: nil,
    simulation_time: nil,
    broadcast_timer: nil
  ]

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_spot_price do
    GenServer.call(__MODULE__, :get_spot_price)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    # Subscribe to home state changes to track production/consumption
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:home")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")  # For simulation time

    # Schedule periodic broadcasts
    timer = Process.send_after(self(), :broadcast_spot_price, @broadcast_interval_ms)

    Logger.info("SpotMarketBroadcaster: Started")
    {:ok, %__MODULE__{broadcast_timer: timer}}
  end

  @impl true
  def handle_call(:get_spot_price, _from, state) do
    spot_data = calculate_current_spot_price(state)
    {:reply, spot_data, state}
  end

  @impl true
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    # Update home's production and consumption
    home_snapshot = %{
      production_kw: home_state.production_kw || 0.0,
      consumption_kw: home_state.consumption_kw || 0.0
    }

    new_homes = Map.put(state.homes, home_id, home_snapshot)
    new_state = %{state | homes: new_homes}

    # Check if price changed significantly
    spot_data = calculate_current_spot_price(new_state)
    price_change = calculate_price_change(state.last_spot_price, spot_data.spot_price)

    if price_change > @significant_change_threshold do
      # Significant change, broadcast immediately
      broadcast_spot_price(spot_data)
      {:noreply, %{new_state | last_spot_price: spot_data.spot_price, last_broadcast_at: DateTime.utc_now()}}
    else
      {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, state) do
    # Extract simulation time
    topic = get_in(event_data, [:details, "topic"]) || ""
    kwargs = event_data[:kwargs] || %{}

    new_state = if String.contains?(topic, "simulation.time") do
      simulation_time = parse_simulation_time(kwargs)
      %{state | simulation_time: simulation_time}
    else
      state
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:broadcast_spot_price, state) do
    # Periodic broadcast
    spot_data = calculate_current_spot_price(state)
    broadcast_spot_price(spot_data)

    # Schedule next broadcast
    timer = Process.send_after(self(), :broadcast_spot_price, @broadcast_interval_ms)

    {:noreply, %{state |
      last_spot_price: spot_data.spot_price,
      last_broadcast_at: DateTime.utc_now(),
      broadcast_timer: timer
    }}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helpers

  defp calculate_current_spot_price(state) do
    # Aggregate total production and consumption
    {total_production_kw, total_consumption_kw} =
      state.homes
      |> Map.values()
      |> Enum.reduce({0.0, 0.0}, fn home, {prod_acc, cons_acc} ->
        {prod_acc + home.production_kw, cons_acc + home.consumption_kw}
      end)

    simulation_time = state.simulation_time || DateTime.utc_now()

    # Calculate spot price using core module
    CortexIqCore.SpotMarket.calculate_spot_price(
      total_production_kw,
      total_consumption_kw,
      simulation_time
    )
  end

  defp calculate_price_change(nil, _new_price), do: 1.0  # First price, treat as significant
  defp calculate_price_change(old_price, new_price) when old_price == 0.0, do: 1.0
  defp calculate_price_change(old_price, new_price) do
    abs((new_price - old_price) / old_price)
  end

  defp broadcast_spot_price(spot_data) do
    # Publish to both PubSub (for dashboard) and WAMP (for bots)
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "market:spot",
      {:spot_price_updated, spot_data}
    )

    # Also publish via WAMP for bot consumption
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "wamp:publish",
      {:publish, "energy.hub.market.spot_price", spot_data}
    )

    Logger.debug("SpotMarketBroadcaster: Spot price ${spot_data.spot_price}/kWh (supply: #{spot_data.total_production_kw}kW, demand: #{spot_data.total_consumption_kw}kW)")
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
