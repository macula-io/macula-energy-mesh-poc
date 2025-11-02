defmodule CortexIqHomes.HomeState do
  @moduledoc """
  Home state management and business logic.

  Holds all business state (battery, contract, balance, weather, etc.) and provides
  functions to calculate solar production, consumption, battery behavior, and
  contract optimization decisions.

  This GenServer is stateful and handles all the "intelligence" of a home:
  - Energy production/consumption simulation
  - Battery charge/discharge optimization
  - Contract evaluation and switching decisions
  - Weather prediction
  - Arbitrage profit tracking

  The HomeCoordinator calls this module to get decisions and state updates,
  then triggers appropriate publishers based on the results.
  """
  use GenServer
  require Logger

  alias CortexIqCore.DateTimeHelpers

  alias CortexIqCore.{Home, Contract, ContractOffer, EnergyBalance, SimulationTime}

  @balance_publish_interval_ms 60_000  # Publish balance every minute

  defstruct [
    :home_id,
    :home,
    :current_simulation_time,
    :current_contract,
    :energy_balance,
    :battery_state_kwh,
    :battery_cycles,
    :provider_offers,
    :last_update,
    :last_balance_publish,
    :paused_until,
    # Connection tracking
    :next_disconnect_time,
    :next_reconnect_time,
    # Trading intelligence
    :current_spot_price,
    :spot_price_history,
    :flexible_load_kwh,
    :flexible_load_schedule,
    :weather_forecast,
    :total_arbitrage_profit,
    # HomeWizard-compatible meter readings
    :cumulative_import_kwh,
    :cumulative_export_kwh,
    # Hourly trade tracking
    :last_trade_hour,
    :hourly_grid_import_kwh,
    :hourly_grid_export_kwh,
    # CortexIQ financial tracking
    :baseline_contract_cost,
    :cortexiq_total_commission,
    :cortexiq_total_savings,
    :cortexiq_net_savings,
    :contract_switches_count,
    # Connection tracking
    connected: true
  ]

  # Client API

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  @doc """
  Update state based on new simulation time tick.

  Returns a map with:
  - `:state_updates` - new state values to store
  - `:measurements` - data to publish via PublishHomeMeasured
  - `:trades` - list of trades to publish (if any)
  - `:arbitrage` - arbitrage profit data to publish (if any)
  - `:balance` - balance data to publish (if due)
  """
  def process_time_tick(home_id, simulation_time) do
    GenServer.call(whereis(home_id), {:process_time_tick, simulation_time}, 30_000)
  end

  @doc """
  Store a contract offer from a provider.
  """
  def store_offer(home_id, provider_id, offer) do
    GenServer.cast(whereis(home_id), {:store_offer, provider_id, offer})
  end

  @doc """
  Update spot price.
  """
  def update_spot_price(home_id, spot_price) do
    GenServer.cast(whereis(home_id), {:update_spot_price, spot_price})
  end

  @doc """
  Confirm contract acceptance (from provider response).

  Returns map with contract switch event data (if applicable) or nil.
  """
  def confirm_contract(home_id, contract_id, provider_id, start_date, end_date, reason) do
    GenServer.call(whereis(home_id), {:confirm_contract, contract_id, provider_id, start_date, end_date, reason})
  end

  @doc """
  Get current state snapshot.
  """
  def get_state(home_id) do
    GenServer.call(whereis(home_id), :get_state)
  end

  def whereis(home_id) do
    case Registry.lookup(CortexIqHomes.Registry, {__MODULE__, home_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    home = Keyword.get(opts, :home) || Home.new(Keyword.fetch!(opts, :home_id))
    home_id = home.id

    Logger.info("Starting HomeState for #{home_id}")

    # Initialize battery at 50-80% charge
    initial_battery_kwh = home.battery_capacity_kwh * (0.5 + :rand.uniform() * 0.3)

    # Calculate flexible load (20% of average daily consumption that can shift)
    flexible_load_kwh = 0.1

    state = %__MODULE__{
      home_id: home_id,
      home: home,
      current_simulation_time: nil,
      current_contract: nil,
      energy_balance: nil,
      battery_state_kwh: initial_battery_kwh,
      battery_cycles: 0.0,
      provider_offers: %{},
      last_update: 0,
      last_balance_publish: 0,
      current_spot_price: nil,
      spot_price_history: [],
      flexible_load_kwh: flexible_load_kwh,
      flexible_load_schedule: %{},
      weather_forecast: predict_weather(),
      total_arbitrage_profit: 0.0,
      cumulative_import_kwh: 0.0,
      cumulative_export_kwh: 0.0,
      last_trade_hour: nil,
      hourly_grid_import_kwh: 0.0,
      hourly_grid_export_kwh: 0.0,
      baseline_contract_cost: nil,
      cortexiq_total_commission: 0.0,
      cortexiq_total_savings: 0.0,
      cortexiq_net_savings: 0.0,
      contract_switches_count: 0,
      paused_until: nil,
      next_disconnect_time: nil,
      next_reconnect_time: nil,
      connected: true
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:process_time_tick, simulation_time}, _from, state) do
    # Calculate energy flows for this tick
    result = process_energy_flows(state, simulation_time)

    # Update state with new values
    new_state = %{state |
      battery_state_kwh: result.battery_kwh,
      battery_cycles: result.battery_cycles,
      energy_balance: result.energy_balance,
      flexible_load_schedule: result.flexible_load_schedule,
      weather_forecast: result.weather_forecast,
      total_arbitrage_profit: result.total_arbitrage_profit,
      cumulative_import_kwh: result.cumulative_import_kwh,
      cumulative_export_kwh: result.cumulative_export_kwh,
      last_trade_hour: result.last_trade_hour,
      hourly_grid_import_kwh: result.hourly_grid_import_kwh,
      hourly_grid_export_kwh: result.hourly_grid_export_kwh,
      last_update: System.monotonic_time(:millisecond),
      last_balance_publish: result.last_balance_publish,
      current_simulation_time: simulation_time
    }

    # Return results for coordinator to publish
    response = %{
      measurements: result.measurements,
      trades: result.trades,
      arbitrage: result.arbitrage,
      balance: result.balance
    }

    {:reply, response, new_state}
  end

  def handle_call({:confirm_contract, contract_id, provider_id, start_date, end_date, reason}, _from, state) do
    case Map.get(state.provider_offers, provider_id) do
      nil ->
        Logger.error("HomeState #{state.home_id}: No offer found for provider #{provider_id}")
        {:reply, nil, state}

      offer ->
        old_contract = state.current_contract
        contract = Contract.from_offer(Map.from_struct(offer), state.home_id, start_date, reason)
        contract = %{contract | id: contract_id, start_date: start_date, end_date: end_date}
        new_balance = EnergyBalance.new(state.home_id, contract.id, start_date)

        # Calculate savings if switching
        {new_state, switch_event} =
          if reason == :switch and old_contract do
            calculate_contract_switch(state, old_contract, contract, start_date)
          else
            {state, nil}
          end

        new_state = %{new_state | current_contract: contract, energy_balance: new_balance}

        {:reply, switch_event, new_state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast({:store_offer, provider_id, offer}, state) do
    new_offers = Map.put(state.provider_offers, provider_id, offer)
    {:noreply, %{state | provider_offers: new_offers}}
  end

  def handle_cast({:update_spot_price, spot_price}, state) do
    # Keep last 24 hours (assuming hourly updates)
    new_history = [spot_price | state.spot_price_history] |> Enum.take(24)
    {:noreply, %{state | current_spot_price: spot_price, spot_price_history: new_history}}
  end

  # Private Functions - Business Logic

  defp process_energy_flows(state, simulation_time) do
    # Calculate time elapsed since last update
    now = System.monotonic_time(:millisecond)
    elapsed_ms = if state.last_update > 0, do: now - state.last_update, else: 100
    elapsed_hours = elapsed_ms / 3_600_000.0

    # Calculate production and consumption
    production_kw = calculate_solar_production(state.home, simulation_time, state.weather_forecast)
    consumption_kw = calculate_consumption(state.home, simulation_time)

    # Simulate battery and grid interaction
    {new_battery_kwh, buy_kwh, sell_kwh, new_balance, new_schedule, new_forecast, new_total_profit} =
      simulate_battery_and_grid_intelligent(
        state,
        production_kw,
        consumption_kw,
        elapsed_hours,
        simulation_time
      )

    # Update cumulative totals (HomeWizard meter readings)
    new_cumulative_import = state.cumulative_import_kwh + buy_kwh
    new_cumulative_export = state.cumulative_export_kwh + sell_kwh

    # Calculate battery cycles
    battery_cycle_increment = abs(buy_kwh + sell_kwh) / (state.home.battery_capacity_kwh * 2)
    new_battery_cycles = state.battery_cycles + battery_cycle_increment

    # DEBUG: Log battery state changes
    battery_pct_old = (state.battery_state_kwh / state.home.battery_capacity_kwh * 100.0) |> Float.round(1)
    battery_pct_new = (new_battery_kwh / state.home.battery_capacity_kwh * 100.0) |> Float.round(1)
    Logger.info("HomeState [#{state.home.id}]: Battery #{battery_pct_old}% → #{battery_pct_new}% (prod=#{Float.round(production_kw, 2)}kW, cons=#{Float.round(consumption_kw, 2)}kW, buy=#{Float.round(buy_kwh, 3)}kWh, sell=#{Float.round(sell_kwh, 3)}kWh)")

    # Build measurement data
    measurements = build_measurement_data(
      state,
      production_kw,
      consumption_kw,
      new_battery_kwh,
      new_battery_cycles,
      buy_kwh,
      sell_kwh,
      elapsed_hours,
      new_cumulative_import,
      new_cumulative_export,
      simulation_time
    )

    # Build trade events (if any)
    trades = if buy_kwh > 0 or sell_kwh > 0 do
      build_trade_events(state, buy_kwh, sell_kwh, simulation_time)
    else
      []
    end

    # Build arbitrage event (if significant)
    arbitrage_profit = new_total_profit - state.total_arbitrage_profit
    arbitrage = if arbitrage_profit > 0.01 do
      %{
        profit: arbitrage_profit,
        total_profit: new_total_profit,
        simulation_time: simulation_time
      }
    else
      nil
    end

    # Check if balance should be published
    {new_last_balance_publish, balance} =
      maybe_build_balance_event(state.last_balance_publish, new_balance, simulation_time)

    # Handle hourly trade accumulation
    {new_hourly_import, new_hourly_export, new_last_trade_hour} =
      accumulate_hourly_trades(
        state.last_trade_hour,
        state.hourly_grid_import_kwh,
        state.hourly_grid_export_kwh,
        buy_kwh,
        sell_kwh,
        simulation_time
      )

    %{
      battery_kwh: new_battery_kwh,
      battery_cycles: new_battery_cycles,
      energy_balance: new_balance,
      flexible_load_schedule: new_schedule,
      weather_forecast: new_forecast,
      total_arbitrage_profit: new_total_profit,
      cumulative_import_kwh: new_cumulative_import,
      cumulative_export_kwh: new_cumulative_export,
      last_trade_hour: new_last_trade_hour,
      hourly_grid_import_kwh: new_hourly_import,
      hourly_grid_export_kwh: new_hourly_export,
      last_balance_publish: new_last_balance_publish,
      measurements: measurements,
      trades: trades,
      arbitrage: arbitrage,
      balance: balance
    }
  end

  # Calculation functions - Solar and Consumption

  defp calculate_solar_production(home, simulation_time, weather_forecast) do
    hour = simulation_time.hour + simulation_time.minute / 60.0

    # Solar production follows sine wave, peak at noon
    # Production hours: roughly 6am to 6pm
    cond do
      hour < 6 or hour >= 18 ->
        0.0

      true ->
        # Sine wave from 6am to 6pm
        hours_from_sunrise = hour - 6
        radians = hours_from_sunrise / 12.0 * :math.pi()
        base_production = :math.sin(radians) * home.solar_capacity_kw

        # Weather forecast affects production
        weather_multiplier = case weather_forecast do
          :sunny -> 0.9 + :rand.uniform() * 0.2  # 90-110% of capacity
          :cloudy -> 0.3 + :rand.uniform() * 0.4  # 30-70% of capacity (reduced)
        end

        max(0.0, base_production * weather_multiplier)
    end
  end

  defp calculate_consumption(_home, simulation_time) do
    hour = simulation_time.hour + simulation_time.minute / 60.0

    # Base load (always on: fridge, etc.)
    base_load_kw = 0.5

    # Morning peak (7-9am): +1.5 kW
    morning_peak =
      if hour >= 7 and hour < 9 do
        1.5 * :math.sin((hour - 7) / 2.0 * :math.pi())
      else
        0.0
      end

    # Evening peak (6-10pm): +2.0 kW
    evening_peak =
      if hour >= 18 and hour < 22 do
        2.0 * :math.sin((hour - 18) / 4.0 * :math.pi())
      else
        0.0
      end

    # Random appliances: ±0.3 kW
    random_load = 0.3 * :rand.uniform()

    base_load_kw + morning_peak + evening_peak + random_load
  end

  defp simulate_battery_and_grid_intelligent(
         state,
         production_kw,
         consumption_kw,
         elapsed_hours,
         simulation_time
       ) do
    # Calculate net power (positive = surplus, negative = deficit)
    net_power_kw = production_kw - consumption_kw
    net_energy_kwh = net_power_kw * elapsed_hours

    # Update weather forecast at midnight
    new_forecast =
      if simulation_time.hour == 0 do
        predict_weather()
      else
        state.weather_forecast
      end

    # Simulate battery and grid transactions
    {new_battery_kwh, buy_kwh, sell_kwh, arbitrage_profit} =
      simulate_battery_logic(
        state.battery_state_kwh,
        state.home.battery_capacity_kwh,
        net_energy_kwh,
        state.current_spot_price,
        state.spot_price_history,
        state.current_contract,
        simulation_time
      )

    # Update total arbitrage profit
    new_total_profit = state.total_arbitrage_profit + arbitrage_profit

    # Update energy balance
    new_balance =
      state.energy_balance
      |> record_buy_transaction(state.current_contract, buy_kwh, simulation_time)
      |> record_sell_transaction(state.current_contract, sell_kwh, simulation_time)

    # Return all updated values
    {new_battery_kwh, buy_kwh, sell_kwh, new_balance, state.flexible_load_schedule,
     new_forecast, new_total_profit}
  end

  defp simulate_battery_logic(
         current_battery_kwh,
         battery_capacity_kwh,
         net_energy_kwh,
         current_spot_price,
         price_history,
         contract,
         simulation_time
       ) do
    # Calculate average spot price for arbitrage decision
    avg_spot_price = calculate_avg_spot_price(price_history)

    # Get current buy/sell prices from contract (or spot if no contract)
    {buy_price, _sell_price} =
      if contract do
        {Contract.buy_price(contract, simulation_time),
         Contract.sell_price(contract, simulation_time)}
      else
        # No contract - would use spot prices
        {current_spot_price || avg_spot_price, (current_spot_price || avg_spot_price) * 0.8}
      end

    # Battery arbitrage logic:
    # - Charge when price below average (buy cheap)
    # - Discharge when price above average (sell high)
    # - Override with net_energy (renewable surplus/deficit takes priority)

    cond do
      # Surplus energy - charge battery or sell to grid
      net_energy_kwh > 0 ->
        available_battery_space = battery_capacity_kwh - current_battery_kwh
        charge_kwh = min(net_energy_kwh, available_battery_space)
        sell_kwh = net_energy_kwh - charge_kwh

        new_battery = current_battery_kwh + charge_kwh
        arbitrage_profit = 0.0  # Charging from own solar, no arbitrage

        {new_battery, 0.0, sell_kwh, arbitrage_profit}

      # Deficit - discharge battery or buy from grid
      net_energy_kwh < 0 ->
        needed_kwh = abs(net_energy_kwh)

        # Arbitrage decision: Should we discharge battery or buy from grid?
        # Discharge if: (1) we have battery charge AND (2) current price > avg (expensive time)
        spot_price = current_spot_price || avg_spot_price
        should_arbitrage = current_battery_kwh > 0.1 && spot_price > avg_spot_price * 1.05

        if should_arbitrage do
          # Discharge battery to avoid buying at high price (or to sell at high price)
          discharge_kwh = min(needed_kwh, current_battery_kwh)
          buy_kwh = needed_kwh - discharge_kwh

          # Calculate arbitrage profit: saved cost vs average price
          # (We charged at lower price, now avoiding buying at higher price)
          arbitrage_profit = discharge_kwh * (buy_price - avg_spot_price) * 0.9  # 90% efficiency

          new_battery = current_battery_kwh - discharge_kwh
          {new_battery, buy_kwh, 0.0, arbitrage_profit}
        else
          # Buy from grid (price is reasonable or battery empty)
          discharge_kwh = min(needed_kwh, current_battery_kwh)
          buy_kwh = needed_kwh - discharge_kwh

          new_battery = current_battery_kwh - discharge_kwh
          {new_battery, buy_kwh, 0.0, 0.0}
        end

      # Perfect balance (rare)
      true ->
        {current_battery_kwh, 0.0, 0.0, 0.0}
    end
  end

  defp calculate_avg_spot_price([]), do: 0.10  # Default base price

  defp calculate_avg_spot_price(price_history) do
    valid_prices = Enum.reject(price_history, &is_nil/1)

    if Enum.empty?(valid_prices) do
      0.10  # Default if no valid prices yet
    else
      Enum.sum(valid_prices) / length(valid_prices)
    end
  end

  defp predict_weather do
    if :rand.uniform() < 0.7, do: :sunny, else: :cloudy
  end

  defp record_buy_transaction(balance, _contract, kwh, _simulation_time) when kwh == 0,
    do: balance

  defp record_buy_transaction(balance, nil, _kwh, _simulation_time), do: balance

  defp record_buy_transaction(balance, contract, kwh, simulation_time) do
    price = Contract.buy_price(contract, simulation_time)
    EnergyBalance.record_buy(balance, kwh, price, simulation_time)
  end

  defp record_sell_transaction(balance, _contract, kwh, _simulation_time) when kwh == 0,
    do: balance

  defp record_sell_transaction(balance, nil, _kwh, _simulation_time), do: balance

  defp record_sell_transaction(balance, contract, kwh, simulation_time) do
    price = Contract.sell_price(contract, simulation_time)
    EnergyBalance.record_sell(balance, kwh, price, simulation_time)
  end

  defp build_measurement_data(
         state,
         production_kw,
         consumption_kw,
         battery_kwh,
         battery_cycles,
         buy_kwh,
         sell_kwh,
         elapsed_hours,
         cumulative_import_kwh,
         cumulative_export_kwh,
         simulation_time
       ) do
    # Calculate grid power
    grid_power_w =
      if elapsed_hours > 0 do
        ((buy_kwh - sell_kwh) / elapsed_hours * 1000.0) |> Float.round(1)
      else
        0.0
      end

    # Determine tariff
    tariff = if SimulationTime.is_day?(simulation_time), do: 1, else: 2

    # Split cumulative by tariff
    {import_t1, import_t2} = split_cumulative_by_tariff(cumulative_import_kwh, tariff)
    {export_t1, export_t2} = split_cumulative_by_tariff(cumulative_export_kwh, tariff)

    # Battery SOC
    state_of_charge_pct = (battery_kwh / state.home.battery_capacity_kwh * 100.0) |> Float.round(1)

    # Electrical measurements (European grid)
    voltage_v = 230.0 + (:rand.uniform() * 4.0 - 2.0)
    current_a = if voltage_v > 0, do: abs(grid_power_w) / voltage_v, else: 0.0
    frequency_hz = 50.0 + (:rand.uniform() * 0.1 - 0.05)
    power_factor = 0.98 + (:rand.uniform() * 0.02)
    apparent_power_va = abs(grid_power_w) / power_factor
    reactive_power_var = :math.sqrt(abs(apparent_power_va * apparent_power_va - grid_power_w * grid_power_w))

    production_w = Float.round(production_kw * 1000, 1)
    consumption_w = Float.round(consumption_kw * 1000, 1)

    %{
      home_id: state.home_id,
      city: state.home.location.city,
      timestamp: DateTimeHelpers.to_iso8601(simulation_time),
      meter_model: "HWE-P1",
      unique_id: state.home_id,
      protocol_version: 50,
      tariff: tariff,
      energy_import_t1_kwh: Float.round(import_t1, 3),
      energy_import_t2_kwh: Float.round(import_t2, 3),
      energy_export_t1_kwh: Float.round(export_t1, 3),
      energy_export_t2_kwh: Float.round(export_t2, 3),
      energy_import_kwh: Float.round(cumulative_import_kwh, 3),
      energy_export_kwh: Float.round(cumulative_export_kwh, 3),
      power_w: grid_power_w,
      voltage_v: Float.round(voltage_v, 1),
      current_a: Float.round(current_a, 2),
      frequency_hz: Float.round(frequency_hz, 2),
      power_factor: Float.round(power_factor, 3),
      apparent_power_va: Float.round(apparent_power_va, 1),
      reactive_power_var: Float.round(reactive_power_var, 1),
      state_of_charge_pct: state_of_charge_pct,
      cycles: Float.round(battery_cycles, 1),
      _production_w: production_w,
      _consumption_w: consumption_w,
      _battery_kwh: Float.round(battery_kwh, 2),
      _battery_capacity_kwh: state.home.battery_capacity_kwh
    }
  end

  defp split_cumulative_by_tariff(total_kwh, current_tariff) do
    case current_tariff do
      1 -> {total_kwh * 0.60, total_kwh * 0.40}
      2 -> {total_kwh * 0.40, total_kwh * 0.60}
      _ -> {total_kwh * 0.50, total_kwh * 0.50}
    end
  end

  defp build_trade_events(state, buy_kwh, sell_kwh, simulation_time) do
    buy_event = build_buy_trade_event(state, buy_kwh, simulation_time)
    sell_event = build_sell_trade_event(state, sell_kwh, simulation_time)
    Enum.reject([buy_event, sell_event], &is_nil/1)
  end

  defp build_buy_trade_event(_state, kwh, _simulation_time) when kwh <= 0, do: nil

  defp build_buy_trade_event(state, kwh, simulation_time) do
    case state.current_contract do
      nil ->
        nil

      contract ->
        price_per_kwh = Contract.buy_price(contract, simulation_time)

        %{
          type: :buy,
          home_id: state.home_id,
          provider_id: contract.provider_id,
          kwh: Float.round(kwh, 3),
          price_per_kwh: price_per_kwh,
          total: Float.round(kwh * price_per_kwh, 2),
          is_day: SimulationTime.is_day?(simulation_time),
          contract_id: contract.id,
          simulation_time: DateTimeHelpers.to_iso8601(simulation_time)
        }
    end
  end

  defp build_sell_trade_event(_state, kwh, _simulation_time) when kwh <= 0, do: nil

  defp build_sell_trade_event(state, kwh, simulation_time) do
    case state.current_contract do
      nil ->
        nil

      contract ->
        price_per_kwh = Contract.sell_price(contract, simulation_time)

        %{
          type: :sell,
          home_id: state.home_id,
          provider_id: contract.provider_id,
          kwh: Float.round(kwh, 3),
          price_per_kwh: price_per_kwh,
          total: Float.round(kwh * price_per_kwh, 2),
          is_day: SimulationTime.is_day?(simulation_time),
          contract_id: contract.id,
          simulation_time: DateTimeHelpers.to_iso8601(simulation_time)
        }
    end
  end

  defp maybe_build_balance_event(last_publish, balance, simulation_time) do
    now = System.monotonic_time(:millisecond)

    if now - last_publish > @balance_publish_interval_ms and balance != nil do
      balance_event = EnergyBalance.to_event(balance, simulation_time)
      {now, balance_event}
    else
      {last_publish, nil}
    end
  end

  defp accumulate_hourly_trades(last_hour, hourly_import, hourly_export, buy_kwh, sell_kwh, simulation_time) do
    current_hour = simulation_time.hour

    # Check if we've crossed an hour boundary
    hour_changed = last_hour != nil and last_hour != current_hour

    if hour_changed do
      # Hour changed - reset accumulators and start accumulating for new hour
      # Note: HomeCoordinator should publish the accumulated trade for the previous hour
      {buy_kwh, sell_kwh, current_hour}
    else
      # Same hour - accumulate
      new_import = hourly_import + buy_kwh
      new_export = hourly_export + sell_kwh
      new_hour = if last_hour == nil, do: current_hour, else: last_hour
      {new_import, new_export, new_hour}
    end
  end

  defp calculate_contract_switch(state, old_contract, new_contract, simulation_time) do
    # Calculate what the old contract would have cost for the next 12 months
    days_in_contract = 365
    baseline_cost = EnergyBalance.project_cost(state.energy_balance, old_contract, days_in_contract)

    # Calculate what the new contract will cost for 12 months
    new_cost = EnergyBalance.project_cost(state.energy_balance, new_contract, days_in_contract)

    # Add switching discount if applicable
    in_discount_window = Contract.in_discount_window?(old_contract, simulation_time)

    discount =
      if in_discount_window do
        new_contract.switching_discount
      else
        0.0
      end

    # Calculate gross savings (what customer saved before CortexIQ commission)
    gross_savings = baseline_cost - new_cost + discount

    # CortexIQ takes 20% commission on savings
    commission_rate = 0.20
    commission = gross_savings * commission_rate

    # Net savings to customer (after commission)
    net_savings = gross_savings - commission

    # Build savings event data
    savings_event = %{
      home_id: state.home_id,
      old_provider_id: old_contract.provider_id,
      new_provider_id: new_contract.provider_id,
      old_contract_id: old_contract.id,
      new_contract_id: new_contract.id,
      baseline_cost: Float.round(baseline_cost, 2),
      new_cost: Float.round(new_cost, 2),
      discount: Float.round(discount, 2),
      gross_savings: Float.round(gross_savings, 2),
      commission: Float.round(commission, 2),
      net_savings: Float.round(net_savings, 2),
      simulation_time: DateTimeHelpers.to_iso8601(simulation_time)
    }

    # Update financial tracking
    new_state_fields = %{
      baseline_contract_cost: baseline_cost,
      cortexiq_total_commission: state.cortexiq_total_commission + commission,
      cortexiq_total_savings: state.cortexiq_total_savings + gross_savings,
      cortexiq_net_savings: state.cortexiq_net_savings + net_savings,
      contract_switches_count: state.contract_switches_count + 1
    }

    {new_state_fields, savings_event}
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
