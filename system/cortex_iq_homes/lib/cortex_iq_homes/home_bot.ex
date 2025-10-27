defmodule CortexIqHomes.HomeBot do
  @moduledoc """
  GenServer representing a home with energy production, consumption, and contract management.

  Each home:
  - Has solar panels and battery storage
  - Consumes energy with realistic daily patterns
  - Manages 12-month contracts with providers
  - Optimizes energy balance (minimize bought - sold)
  - Subscribes to provider offers and switches contracts when beneficial

  Publishes to WAMP topics:
  - be.cortexiq.home.measured (HomeWizard-compatible smart meter data)
  - be.cortexiq.balance.updated
  - be.cortexiq.market.contract_signed
  - be.cortexiq.market.contract_switched
  - be.cortexiq.market.contract_expired
  - be.cortexiq.market.trade_executed
  - be.cortexiq.arbitrage.profit_realized

  Subscribes to:
  - be.cortexiq.simulation.time_advanced
  - be.cortexiq.market.contract_proposed
  - be.cortexiq.market.spot_price_updated

  The measurement event (be.cortexiq.home.measured) is compatible with HomeWizard Energy
  smart meters, allowing future integration with real IoT hardware.
  """

  use GenServer
  require Logger

  alias CortexIqCore.{Home, Contract, ContractOffer, EnergyBalance, SimulationTime, SpotMarket}
  alias MaculaSdk.Wamp.Client

  defstruct [
    :home_id,
    :home,
    :wamp_client,
    :realm,
    :current_simulation_time,
    :current_contract,
    :energy_balance,
    :battery_state_kwh,
    :provider_offers,
    :last_update,
    :last_balance_publish,
    :paused_until,                 # Monotonic time until which this home should pause after reset
    # Trading intelligence fields
    :current_spot_price,
    :spot_price_history,          # Last 24 hours of prices for moving average
    :flexible_load_kwh,            # 20% of base load that can shift ±2 hours
    :flexible_load_schedule,       # Map of hour -> scheduled flexible load
    :weather_forecast,             # :sunny or :cloudy prediction for tomorrow
    :total_arbitrage_profit,       # Cumulative profit from battery trading
    # HomeWizard-compatible meter readings (cumulative)
    :cumulative_import_kwh,        # Total energy imported from grid (like real meter)
    :cumulative_export_kwh,        # Total energy exported to grid (like real meter)
    # Hourly trade accumulation (for be.cortexiq.home.traded events)
    :last_trade_hour,              # Track which hour we last published trade for
    :hourly_grid_import_kwh,       # Accumulate imports over current hour
    :hourly_grid_export_kwh        # Accumulate exports over current hour
  ]

  # Update intervals (real-time milliseconds)
  @update_interval_ms 100           # ~3 simulation hours at 105,120x
  @balance_publish_interval_ms 5000 # Publish balance every 5 seconds

  ## Client API

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  def get_state(home_id) do
    GenServer.call(via_tuple(home_id), :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    home = Keyword.get(opts, :home) || Home.new(Keyword.fetch!(opts, :home_id))
    home_id = home.id
    realm = Keyword.get(opts, :realm, "energy.hub")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    Logger.info("Starting HomeBotNew for #{home_id}")
    Logger.info("  Location: #{home.location.city}, #{home.location.postal_code}")
    Logger.info("  Solar capacity: #{Float.round(home.solar_capacity_kw, 1)} kW")
    Logger.info("  Battery capacity: #{Float.round(home.battery_capacity_kwh, 1)} kWh")

    # Connect to WAMP
    {:ok, wamp_client} =
      MaculaSdk.Wamp.Client.start_link(
        url: bondy_url,
        realm: realm
      )

    # Initialize battery at 50-80% charge
    initial_battery_kwh = home.battery_capacity_kwh * (0.5 + :rand.uniform() * 0.3)

    # Calculate flexible load (20% of average daily consumption that can shift)
    # Average base load = 0.5 kW, so 20% = 0.1 kW
    flexible_load_kwh = 0.1

    state = %__MODULE__{
      home_id: home_id,
      home: home,
      wamp_client: wamp_client,
      realm: realm,
      current_simulation_time: nil,
      current_contract: nil,
      energy_balance: nil,
      battery_state_kwh: initial_battery_kwh,
      provider_offers: %{},
      last_update: 0,
      last_balance_publish: 0,
      # Initialize trading intelligence
      current_spot_price: nil,
      spot_price_history: [],
      flexible_load_kwh: flexible_load_kwh,
      flexible_load_schedule: %{},
      weather_forecast: predict_weather(),
      total_arbitrage_profit: 0.0,
      # Initialize HomeWizard-compatible meter readings
      cumulative_import_kwh: 0.0,
      cumulative_export_kwh: 0.0,
      # Initialize hourly trade tracking
      last_trade_hour: nil,
      hourly_grid_import_kwh: 0.0,
      hourly_grid_export_kwh: 0.0
    }

    # Defer subscriptions with random staggered delay to simulate realistic startup
    # This prevents all homes from coming online simultaneously
    max_delay_ms = System.get_env("HOME_STARTUP_DELAY_MAX", "30000") |> String.to_integer()
    startup_delay_ms = :rand.uniform(max_delay_ms)

    Logger.info("Home #{home_id}: Will come online in #{Float.round(startup_delay_ms / 1000, 1)}s")
    Process.send_after(self(), :subscribe, startup_delay_ms)

    # Schedule first update
    Process.send_after(self(), :update, @update_interval_ms)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    # Now that connection should be ready, subscribe to topics
    Logger.info("Home #{state.home_id}: Subscribing to WAMP topics")

    with :ok <- subscribe_to_simulation_time(state.wamp_client),
         :ok <- subscribe_to_simulation_reset(state.wamp_client),
         :ok <- subscribe_to_all_contract_offers(state.wamp_client),
         :ok <- subscribe_to_market_spot_price(state.wamp_client),
         :ok <- subscribe_to_contract_responses(state.wamp_client) do
      Logger.info("Home #{state.home_id}: Subscribed to all topics")
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.warning("Home #{state.home_id}: Failed to subscribe: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :subscribe, 500)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:wamp_event, "be.cortexiq.simulation.time_advanced", _args, kwargs, _details}, state) do
    # Parse simulation time from event
    {:ok, sim_time, _} = DateTime.from_iso8601(kwargs["simulation_time"])

    Logger.info("Home #{state.home_id} received simulation time: #{DateTime.to_time(sim_time)}")

    # Check if we're paused (staggered startup after reset)
    now = System.monotonic_time(:millisecond)
    is_paused = state.paused_until && now < state.paused_until

    new_state =
      if is_paused do
        # Still paused - ignore simulation time updates completely
        Logger.debug("Home #{state.home_id}: Still paused, ignoring simulation time")
        state
      else
        # Clear pause flag if we just resumed
        state = if state.paused_until, do: %{state | paused_until: nil}, else: state

        # Check if this is the first simulation time received (or first after reset)
        if state.current_simulation_time == nil do
          Logger.info("Home #{state.home_id}: First simulation time after pause, initializing")
          # Initialize contract and energy balance on first simulation time (after pause)
          initialize_contract_and_balance(state, sim_time)
        else
          %{state | current_simulation_time: sim_time}
        end
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_event, "be.cortexiq.simulation.reset", _args, _kwargs, _details}, state) do
    Logger.info("Home #{state.home_id}: Received SIMULATION RESET - clearing state")

    # Add staggered delay before resuming operations (like startup)
    max_delay_ms = System.get_env("HOME_STARTUP_DELAY_MAX", "30000") |> String.to_integer()
    delay_ms = :rand.uniform(max_delay_ms)
    paused_until = System.monotonic_time(:millisecond) + delay_ms

    Logger.info("Home #{state.home_id}: Will resume operations in #{Float.round(delay_ms / 1000, 1)}s after reset")

    # Reset to initial state (clear contract, balance, simulation time)
    new_state = %{state |
      current_simulation_time: nil,
      current_contract: nil,
      energy_balance: nil,
      provider_offers: %{},
      total_arbitrage_profit: 0.0,
      cumulative_import_kwh: 0.0,
      cumulative_export_kwh: 0.0,
      paused_until: paused_until
    }

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_event, topic, _args, kwargs, _details}, state) do
    Logger.info("Home #{state.home_id} received WAMP event from topic: #{topic}")

    cond do
      String.contains?(topic, ".contract_proposed") ->
        # Provider published a contract offer
        offer = ContractOffer.from_event(kwargs)
        Logger.info("Home #{state.home_id} received contract offer from #{offer.provider_id}")

        # Store offer
        provider_offers = Map.put(state.provider_offers, offer.provider_id, offer)
        {:noreply, %{state | provider_offers: provider_offers}}

      String.contains?(topic, ".spot_price_updated") ->
        # Market spot price updated
        spot_price = kwargs["spot_price"]
        Logger.debug("Home #{state.home_id} received market spot price: $#{spot_price}/kWh")

        # Update spot price history (keep last 24 data points = ~72 simulation hours)
        new_history = [spot_price | state.spot_price_history] |> Enum.take(24)

        {:noreply, %{state | current_spot_price: spot_price, spot_price_history: new_history}}

      String.ends_with?(topic, ".market.contract_confirmed") ->
        # Provider confirmed our contract signing request
        home_id = kwargs["home_id"]

        # Only process if this is for us
        if home_id == state.home_id do
          contract_id = kwargs["contract_id"]
          provider_id = kwargs["provider_id"]
          {:ok, start_date, _} = DateTime.from_iso8601(kwargs["start_date"])
          {:ok, end_date, _} = DateTime.from_iso8601(kwargs["end_date"])
          reason = String.to_existing_atom(kwargs["reason"])

          Logger.info("Home #{state.home_id}: Contract #{contract_id} confirmed by provider #{provider_id}")

          # Reconstruct contract from event data
          offer = Map.get(state.provider_offers, provider_id)

          if offer do
            old_contract = state.current_contract

            # Create contract from offer
            contract = Contract.from_offer(Map.from_struct(offer), state.home_id, start_date, reason)

            # Override with confirmed contract ID and dates
            contract = %{contract | id: contract_id, start_date: start_date, end_date: end_date}

            # Reset energy balance for new contract period
            new_balance = EnergyBalance.new(state.home_id, contract.id, start_date)

            Logger.info("Home #{state.home_id}: Switched from #{old_contract && old_contract.provider_id} to #{provider_id}")

            # Publish contract switched event if this was a switch
            if reason == :switch and old_contract do
              publish_contract_switched(state, old_contract, contract, start_date)
            end

            {:noreply, %{state | current_contract: contract, energy_balance: new_balance}}
          else
            Logger.error("Home #{state.home_id}: No offer found for provider #{provider_id}")
            {:noreply, state}
          end
        else
          {:noreply, state}
        end

      String.ends_with?(topic, ".market.contract_rejected") ->
        # Provider rejected our contract signing request
        home_id = kwargs["home_id"]

        # Only process if this is for us
        if home_id == state.home_id do
          provider_id = kwargs["provider_id"]
          reason = kwargs["reason"]

          Logger.warning("Home #{state.home_id}: Contract request rejected by provider #{provider_id}: #{reason}")

          # Could implement retry logic or fallback to another provider
          {:noreply, state}
        else
          {:noreply, state}
        end

      true ->
        Logger.warning("Home #{state.home_id} received unknown event from #{topic}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:update, state) do
    # Check if we're paused (staggered startup after reset)
    now = System.monotonic_time(:millisecond)
    is_paused = state.paused_until && now < state.paused_until

    new_state =
      if is_paused do
        # Still paused - skip all operations
        state
      else
        # Clear pause flag if we just resumed
        state = if state.paused_until, do: %{state | paused_until: nil}, else: state

        with %DateTime{} = sim_time <- state.current_simulation_time do
          # Simulate energy production, consumption, and battery
          state
          |> simulate_production_and_consumption(sim_time)
          |> check_contract_expiry(sim_time)
          |> evaluate_contract_switching(sim_time)
          |> maybe_publish_balance(sim_time)
        else
          _ ->
            Logger.debug("Home #{state.home_id}: No simulation time yet, skipping update")
            state
        end
      end

    # Schedule next update
    Process.send_after(self(), :update, @update_interval_ms)

    {:noreply, new_state}
  end

  ## Private Functions - Subscription

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, home_id}}
  end

  defp subscribe_to_simulation_time(wamp_client) do
    topic = "be.cortexiq.simulation.time_advanced"
    Logger.info("Subscribing to #{topic}")

    # Capture the home bot PID (NOT the WAMP client PID)
    home_bot_pid = self()

    handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_simulation_reset(wamp_client) do
    topic = "be.cortexiq.simulation.reset"
    Logger.info("Subscribing to #{topic}")

    home_bot_pid = self()

    handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_all_contract_offers(wamp_client) do
    # Subscribe to single market topic for all contract offers
    topic = "be.cortexiq.market.contract_proposed"
    Logger.info("Subscribing to #{topic}")

    home_bot_pid = self()

    handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_market_spot_price(wamp_client) do
    topic = "be.cortexiq.market.spot_price_updated"
    Logger.info("Subscribing to #{topic}")

    home_bot_pid = self()

    handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_contract_responses(wamp_client) do
    home_bot_pid = self()

    # Subscribe to contract_confirmed
    confirmed_topic = "be.cortexiq.market.contract_confirmed"
    Logger.info("Subscribing to #{confirmed_topic}")

    confirmed_handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, confirmed_topic, [], kwargs, %{}})
    end

    # Subscribe to contract_rejected
    rejected_topic = "be.cortexiq.market.contract_rejected"
    Logger.info("Subscribing to #{rejected_topic}")

    rejected_handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, rejected_topic, [], kwargs, %{}})
    end

    with {:ok, _sub_id1} <- Client.subscribe(wamp_client, confirmed_topic, confirmed_handler),
         {:ok, _sub_id2} <- Client.subscribe(wamp_client, rejected_topic, rejected_handler) do
      :ok
    end
  end

  ## Private Functions - Initialization

  defp initialize_contract_and_balance(state, simulation_time) do
    # Start with a random contract (simulate existing customer)
    # Contract started sometime in the past year
    days_ago = :rand.uniform(365)
    contract_start = DateTime.add(simulation_time, -days_ago * 86400, :second)

    # Pick a random provider
    all_providers = CortexIqCore.Provider.all()
    provider = Enum.random(all_providers)

    # Create initial contract with random pricing
    offer = %{
      provider_id: provider.id,
      offer_id: "initial_offer",
      day_buy_price: provider.base_day_buy_price,
      night_buy_price: provider.base_night_buy_price,
      day_sell_price: provider.base_day_sell_price,
      night_sell_price: provider.base_night_sell_price,
      switching_discount: provider.switching_discount,
      minimum_monthly_kwh: provider.minimum_monthly_kwh,
      duration_months: 12
    }

    contract = Contract.from_offer(offer, state.home_id, contract_start, :new)

    # Initialize energy balance
    energy_balance = EnergyBalance.new(state.home_id, contract.id, contract_start)

    Logger.info("Home #{state.home_id} initialized with contract from #{provider.id}, started #{days_ago} days ago")

    new_state = %{
      state
      | current_simulation_time: simulation_time,
        current_contract: contract,
        energy_balance: energy_balance
    }

    # Publish home initialization event so dashboard knows about this home
    publish_home_initialized(new_state, simulation_time)

    # Publish initial contract to dashboard so it knows about it
    publish_initial_contract(new_state, contract, provider.id, simulation_time)

    new_state
  end

  ## Private Functions - Simulation

  defp simulate_production_and_consumption(state, simulation_time) do
    # Calculate solar production (kW) based on time of day and weather forecast
    production_kw = calculate_solar_production(state.home, simulation_time, state.weather_forecast)

    # Calculate base consumption (kW) based on time of day
    base_consumption_kw = calculate_consumption(state.home, simulation_time)

    # Add demand response: shift flexible load to cheapest hours
    {consumption_kw, new_schedule} = apply_demand_response(
      base_consumption_kw,
      state.flexible_load_kwh,
      state.flexible_load_schedule,
      state.spot_price_history,
      simulation_time
    )

    # Calculate net power (positive = surplus, negative = deficit)
    net_power_kw = production_kw - consumption_kw

    # Calculate time elapsed since last update (~3 simulation hours)
    # At 105,120x speed, 100ms real-time = 10,512 seconds = ~2.92 hours simulation
    elapsed_hours = 10_512 / 3600.0

    # Production forecasting: predict tomorrow's weather at midnight
    new_forecast = if simulation_time.hour == 0 do
      predict_weather()
    else
      state.weather_forecast
    end

    # Update battery and calculate grid transactions (with arbitrage logic)
    {new_battery_kwh, buy_kwh, sell_kwh, arbitrage_profit} =
      simulate_battery_and_grid_intelligent(
        state.battery_state_kwh,
        state.home.battery_capacity_kwh,
        net_power_kw,
        elapsed_hours,
        state.current_spot_price,
        state.spot_price_history,
        state.current_contract,
        simulation_time
      )

    # Update total arbitrage profit
    new_total_profit = state.total_arbitrage_profit + arbitrage_profit

    # Record energy transactions in balance
    new_balance =
      state.energy_balance
      |> record_buy_transaction(state.current_contract, buy_kwh, simulation_time)
      |> record_sell_transaction(state.current_contract, sell_kwh, simulation_time)

    # Update cumulative meter readings (like real smart meters)
    new_cumulative_import = state.cumulative_import_kwh + buy_kwh
    new_cumulative_export = state.cumulative_export_kwh + sell_kwh

    # Log calculated values
    Logger.info("Home #{state.home_id} @ #{DateTime.to_time(simulation_time)}: prod=#{Float.round(production_kw, 2)}kW cons=#{Float.round(consumption_kw, 2)}kW bat=#{Float.round(new_battery_kwh, 1)}kWh")

    # Publish single HomeWizard-compatible measurement event
    publish_measurement(
      state,
      production_kw,
      consumption_kw,
      new_battery_kwh,
      buy_kwh,
      sell_kwh,
      elapsed_hours,
      new_cumulative_import,
      new_cumulative_export,
      simulation_time
    )

    # Publish trades for market tracking
    if buy_kwh > 0 or sell_kwh > 0 do
      publish_trades(state, buy_kwh, sell_kwh, simulation_time)
    end

    # Publish arbitrage profit if significant
    if arbitrage_profit > 0.01 do
      publish_arbitrage_profit(state, arbitrage_profit, new_total_profit, simulation_time)
    end

    # Accumulate hourly trades and check for hour boundary
    {new_hourly_import, new_hourly_export, new_last_trade_hour} =
      handle_hourly_trade_accumulation(
        state.last_trade_hour,
        state.hourly_grid_import_kwh,
        state.hourly_grid_export_kwh,
        buy_kwh,
        sell_kwh,
        state.current_contract,
        simulation_time,
        state.wamp_client,
        state.home_id
      )

    %{state |
      battery_state_kwh: new_battery_kwh,
      energy_balance: new_balance,
      flexible_load_schedule: new_schedule,
      weather_forecast: new_forecast,
      total_arbitrage_profit: new_total_profit,
      cumulative_import_kwh: new_cumulative_import,
      cumulative_export_kwh: new_cumulative_export,
      last_trade_hour: new_last_trade_hour,
      hourly_grid_import_kwh: new_hourly_import,
      hourly_grid_export_kwh: new_hourly_export,
      last_update: System.monotonic_time(:millisecond)
    }
  end

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

  defp simulate_battery_and_grid(current_battery_kwh, battery_capacity_kwh, net_power_kw, elapsed_hours) do
    # Energy available/needed over the time period
    net_energy_kwh = net_power_kw * elapsed_hours

    cond do
      # Surplus energy - charge battery or sell to grid
      net_energy_kwh > 0 ->
        available_battery_space = battery_capacity_kwh - current_battery_kwh
        charge_kwh = min(net_energy_kwh, available_battery_space)
        sell_kwh = net_energy_kwh - charge_kwh

        new_battery = current_battery_kwh + charge_kwh
        {new_battery, 0.0, sell_kwh}

      # Deficit - discharge battery or buy from grid
      net_energy_kwh < 0 ->
        needed_kwh = abs(net_energy_kwh)
        discharge_kwh = min(needed_kwh, current_battery_kwh)
        buy_kwh = needed_kwh - discharge_kwh

        new_battery = current_battery_kwh - discharge_kwh
        {new_battery, buy_kwh, 0.0}

      # Perfect balance (rare)
      true ->
        {current_battery_kwh, 0.0, 0.0}
    end
  end

  defp record_buy_transaction(balance, _contract, kwh, _simulation_time) when kwh == 0, do: balance
  defp record_buy_transaction(balance, nil, _kwh, _simulation_time), do: balance

  defp record_buy_transaction(balance, contract, kwh, simulation_time) do
    price = Contract.buy_price(contract, simulation_time)
    EnergyBalance.record_buy(balance, kwh, price, simulation_time)
  end

  defp record_sell_transaction(balance, _contract, kwh, _simulation_time) when kwh == 0, do: balance
  defp record_sell_transaction(balance, nil, _kwh, _simulation_time), do: balance

  defp record_sell_transaction(balance, contract, kwh, simulation_time) do
    price = Contract.sell_price(contract, simulation_time)
    EnergyBalance.record_sell(balance, kwh, price, simulation_time)
  end

  ## Private Functions - Contract Management

  defp check_contract_expiry(state, simulation_time) do
    with %Contract{} = contract <- state.current_contract do
      if Contract.expired?(contract, simulation_time) do
        Logger.info("Home #{state.home_id}: Contract expired, switching to best available offer")

        # Publish contract_expired event
        publish_contract_expired(state, contract, simulation_time)

        # Contract expired - automatically switch to best offer
        case find_best_offer(state.provider_offers, state.energy_balance, state.current_spot_price, simulation_time) do
          {provider_id, offer} ->
            sign_new_contract(state, offer, provider_id, :renewal, simulation_time)

          nil ->
            Logger.warning("Home #{state.home_id}: No offers available after expiry, staying on spot market")
            %{state | current_contract: nil}
        end
      else
        state
      end
    else
      _ -> state
    end
  end

  defp evaluate_contract_switching(state, simulation_time) do
    # Only evaluate if we have a contract and offers available
    with %Contract{} = current_contract <- state.current_contract,
         false <- map_size(state.provider_offers) == 0 do
      # Find best alternative offer
      case find_best_offer(state.provider_offers, state.energy_balance, state.current_spot_price, simulation_time) do
        {provider_id, best_offer} ->
          # Calculate if switching is worthwhile
          current_days_remaining = Contract.days_remaining(current_contract, simulation_time)

          if should_switch_contract?(
               current_contract,
               best_offer,
               state.energy_balance,
               current_days_remaining,
               simulation_time
             ) do
            Logger.info(
              "Home #{state.home_id}: Switching from #{current_contract.provider_id} to #{provider_id} " <>
                "(#{current_days_remaining} days early)"
            )

            sign_new_contract(state, best_offer, provider_id, :switch, simulation_time)
          else
            state
          end

        nil ->
          state
      end
    else
      _ -> state
    end
  end

  defp find_best_offer(provider_offers, _energy_balance, _spot_price, _simulation_time) when map_size(provider_offers) == 0,
    do: nil

  defp find_best_offer(_provider_offers, _energy_balance, nil, _simulation_time) do
    # No spot price yet - can't evaluate dynamic contracts properly
    # Wait until we receive market data
    nil
  end

  defp find_best_offer(provider_offers, _energy_balance, spot_price, _simulation_time) do
    # Simple heuristic: pick offer with lowest average buy price
    # In a more sophisticated version, we'd project costs over contract period

    Enum.min_by(provider_offers, fn {_provider_id, offer} ->
      ContractOffer.avg_buy_price(offer, spot_price)
    end, fn -> nil end)
  end

  defp should_switch_contract?(current_contract, new_offer, energy_balance, days_remaining, simulation_time) do
    # Calculate projected costs for remainder of current contract vs new contract

    # Current contract projected cost
    current_proj_cost = EnergyBalance.project_cost(energy_balance, current_contract, days_remaining)

    # New contract projected cost (12 months)
    new_contract = Contract.from_offer(Map.from_struct(new_offer), "temp", simulation_time)
    new_proj_cost = EnergyBalance.project_cost(energy_balance, new_contract, 365)

    # Normalize to daily costs
    current_daily_cost = current_proj_cost / max(1, days_remaining)
    new_daily_cost = new_proj_cost / 365

    # Switch if new contract saves more than $0.50/day on average
    savings_per_day = current_daily_cost - new_daily_cost

    # Factor in switching discount (only if not in discount window)
    in_discount_window = Contract.in_discount_window?(current_contract, simulation_time)
    discount = if in_discount_window, do: new_offer.switching_discount, else: 0.0

    total_savings = savings_per_day * 365 + discount

    Logger.debug(
      "Home: Evaluating switch - Current: $#{Float.round(current_daily_cost, 2)}/day, " <>
        "New: $#{Float.round(new_daily_cost, 2)}/day, " <>
        "Total savings: $#{Float.round(total_savings, 2)}"
    )

    # Switch if total savings > $50 over the year
    total_savings > 50.0
  end

  defp sign_new_contract(state, offer, provider_id, reason, simulation_time) do
    # Call provider RPC to accept contract offer
    call_accept_offer_rpc(state, provider_id, offer.offer_id, reason, simulation_time)

    # State will be updated when we receive contract_confirmed event
    # For now, just return current state
    state
  end

  ## Private Functions - Publishing

  defp publish_measurement(
         state,
         production_kw,
         consumption_kw,
         battery_kwh,
         buy_kwh,
         sell_kwh,
         elapsed_hours,
         cumulative_import_kwh,
         cumulative_export_kwh,
         simulation_time
       ) do
    topic = "be.cortexiq.home.measured"

    # Calculate grid power (HomeWizard reports net power at grid connection)
    # Positive = importing from grid, Negative = exporting to grid
    # Grid power in watts = (energy imported - energy exported) / time * 1000
    grid_power_w =
      if elapsed_hours > 0 do
        ((buy_kwh - sell_kwh) / elapsed_hours * 1000.0) |> Float.round(1)
      else
        0.0
      end

    # Battery state of charge percentage
    state_of_charge_pct = (battery_kwh / state.home.battery_capacity_kwh * 100.0) |> Float.round(1)

    # HomeWizard-compatible measurement payload
    event = %{
      home_id: state.home_id,
      city: state.home.location.city,
      timestamp: DateTime.to_iso8601(simulation_time),
      # Grid connection power (what HomeWizard reports)
      power_w: grid_power_w,
      # Cumulative totals (like real meter readings)
      energy_import_kwh: Float.round(cumulative_import_kwh, 3),
      energy_export_kwh: Float.round(cumulative_export_kwh, 3),
      # Battery state
      state_of_charge_pct: state_of_charge_pct,
      # Internal details (optional, for debugging/visualization)
      _internal: %{
        production_w: Float.round(production_kw * 1000, 1),
        consumption_w: Float.round(consumption_kw * 1000, 1),
        battery_kwh: Float.round(battery_kwh, 2),
        battery_capacity_kwh: state.home.battery_capacity_kwh
      }
    }

    Logger.info("Publishing measurement: prod_w=#{event._internal.production_w} cons_w=#{event._internal.consumption_w} soc=#{event.state_of_charge_pct}%")
    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp maybe_publish_balance(state, simulation_time) do
    now = System.monotonic_time(:millisecond)

    if now - state.last_balance_publish > @balance_publish_interval_ms do
      publish_balance(state, simulation_time)
      %{state | last_balance_publish: now}
    else
      state
    end
  end

  defp publish_balance(state, simulation_time) do
    topic = "be.cortexiq.balance.updated"
    event = EnergyBalance.to_event(state.energy_balance, simulation_time)
    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp call_accept_offer_rpc(state, provider_id, offer_id, reason, simulation_time) do
    procedure = "be.cortexiq.provider.#{provider_id}.accept_offer"

    kwargs = %{
      "home_id" => state.home_id,
      "offer_id" => offer_id,
      "reason" => Atom.to_string(reason),
      "simulation_time" => DateTime.to_iso8601(simulation_time)
    }

    Logger.info("Home #{state.home_id}: Calling RPC #{procedure} to accept offer #{offer_id}")

    # Make async RPC call - result will come via WAMP event handler
    # Provider will respond and publish contract_confirmed or contract_rejected
    case Client.call(state.wamp_client, procedure, [], kwargs, %{}) do
      {:ok, result} ->
        Logger.info("Home #{state.home_id}: RPC call successful - #{inspect(result)}")
      {:error, reason} ->
        Logger.error("Home #{state.home_id}: RPC call failed - #{inspect(reason)}")
    end
  end

  defp publish_home_initialized(state, simulation_time) do
    topic = "be.cortexiq.home.initialized"

    event = %{
      home_id: state.home_id,
      home_name: state.home.name,
      address: %{
        street: state.home.location.street,
        city: state.home.location.city,
        postal_code: state.home.location.postal_code
      },
      region: to_string(state.home.location.region),
      solar_capacity_kw: state.home.solar_capacity_kw,
      battery_capacity_kwh: state.home.battery_capacity_kwh,
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
    Logger.info("Home #{state.home_id}: Published initialization event (#{state.home.location.city})")
  end

  defp publish_initial_contract(state, contract, provider_id, simulation_time) do
    # Publish in the same format as contract_confirmed so dashboard can track it
    topic = "be.cortexiq.market.contract_confirmed"

    event = %{
      contract_id: contract.id,
      home_id: state.home_id,
      home_name: state.home.name,
      provider_id: provider_id,
      offer_id: contract.offer_id,
      start_date: DateTime.to_iso8601(contract.start_date),
      end_date: DateTime.to_iso8601(contract.end_date),
      reason: "initial",  # Mark as initial contract
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
    Logger.info("Home #{state.home_id}: Published initial contract to dashboard")
  end

  defp publish_contract_switched(state, old_contract, new_contract, simulation_time) do
    topic = "be.cortexiq.market.contract_switched"

    days_before_expiry = Contract.days_remaining(old_contract, simulation_time)

    event = %{
      home_id: state.home_id,
      home_name: state.home.name,
      from_contract_id: old_contract.id,
      from_provider_id: old_contract.provider_id,
      to_contract_id: new_contract.id,
      to_provider_id: new_contract.provider_id,
      days_before_expiry: days_before_expiry,
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_contract_expired(state, contract, simulation_time) do
    topic = "be.cortexiq.market.contract_expired"

    event = %{
      home_id: state.home_id,
      contract_id: contract.id,
      provider_id: contract.provider_id,
      start_date: DateTime.to_iso8601(contract.start_date),
      end_date: DateTime.to_iso8601(contract.end_date),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_trades(state, buy_kwh, sell_kwh, simulation_time) do
    if state.current_contract do
      if buy_kwh > 0 do
        publish_trade(state, :buy, buy_kwh, simulation_time)
      end

      if sell_kwh > 0 do
        publish_trade(state, :sell, sell_kwh, simulation_time)
      end
    end
  end

  defp publish_trade(state, type, kwh, simulation_time) do
    topic = "be.cortexiq.market.trade_executed"

    price_per_kwh =
      if type == :buy do
        Contract.buy_price(state.current_contract, simulation_time)
      else
        Contract.sell_price(state.current_contract, simulation_time)
      end

    event = %{
      home_id: state.home_id,
      provider_id: state.current_contract.provider_id,
      type: Atom.to_string(type),
      kwh: Float.round(kwh, 3),
      price_per_kwh: price_per_kwh,
      total: Float.round(kwh * price_per_kwh, 2),
      is_day: SimulationTime.is_day?(simulation_time),
      contract_id: state.current_contract.id,
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_arbitrage_profit(state, profit, total_profit, simulation_time) do
    topic = "be.cortexiq.arbitrage.profit_realized"

    event = %{
      home_id: state.home_id,
      city: state.home.location.city,
      profit: Float.round(profit, 2),
      total_profit: Float.round(total_profit, 2),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  ## Private Functions - Hourly Trade Accumulation

  defp handle_hourly_trade_accumulation(
         last_trade_hour,
         hourly_import,
         hourly_export,
         buy_kwh,
         sell_kwh,
         current_contract,
         simulation_time,
         wamp_client,
         home_id
       ) do
    current_hour = simulation_time.hour

    # Check if we've crossed an hour boundary
    hour_changed = last_trade_hour != nil and last_trade_hour != current_hour

    if hour_changed do
      # Publish accumulated trade for the previous hour
      publish_hourly_trade(
        home_id,
        current_contract,
        hourly_import,
        hourly_export,
        last_trade_hour,
        simulation_time,
        wamp_client
      )

      # Reset accumulators and start accumulating for new hour
      {buy_kwh, sell_kwh, current_hour}
    else
      # Same hour - accumulate
      new_import = hourly_import + buy_kwh
      new_export = hourly_export + sell_kwh
      new_hour = if last_trade_hour == nil, do: current_hour, else: last_trade_hour
      {new_import, new_export, new_hour}
    end
  end

  defp publish_hourly_trade(
         home_id,
         nil,
         _hourly_import,
         _hourly_export,
         _last_hour,
         _simulation_time,
         _wamp_client
       ) do
    # Skip if no contract
    Logger.debug("Home #{home_id}: Skipping hourly trade - no active contract")
    :ok
  end

  defp publish_hourly_trade(
         home_id,
         contract,
         hourly_import,
         hourly_export,
         last_hour,
         simulation_time,
         wamp_client
       ) do
    # Calculate the time for the completed hour (use last hour, not current)
    hour_time = %{simulation_time | hour: last_hour, minute: 0, second: 0, microsecond: {0, 6}}

    is_day = SimulationTime.is_day?(hour_time)

    # Get pricing for the completed hour
    import_price = Contract.buy_price(contract, hour_time)
    export_price = Contract.sell_price(contract, hour_time)

    import_cost = hourly_import * import_price
    export_revenue = hourly_export * export_price
    net_cost = import_cost - export_revenue

    topic = "be.cortexiq.home.traded"

    event = %{
      home_id: home_id,
      provider_id: contract.provider_id,
      contract_id: contract.id,
      simulation_time: DateTime.to_iso8601(hour_time),
      simulation_hour: last_hour,
      grid_import_kwh: Float.round(hourly_import, 3),
      grid_export_kwh: Float.round(hourly_export, 3),
      import_price_per_kwh: Float.round(import_price, 4),
      export_price_per_kwh: Float.round(export_price, 4),
      import_cost: Float.round(import_cost, 2),
      export_revenue: Float.round(export_revenue, 2),
      net_cost: Float.round(net_cost, 2),
      is_day: is_day
    }

    Logger.info(
      "Home #{home_id}: Hourly trade for hour #{last_hour} - " <>
        "import: #{Float.round(hourly_import, 2)} kWh, " <>
        "export: #{Float.round(hourly_export, 2)} kWh, " <>
        "net cost: $#{Float.round(net_cost, 2)}"
    )

    Client.publish(wamp_client, topic, [], event, %{})
  end

  ## Private Functions - Trading Intelligence

  defp predict_weather do
    # Simple forecast: 80% sunny, 20% cloudy
    if :rand.uniform() < 0.80, do: :sunny, else: :cloudy
  end

  defp apply_demand_response(base_consumption_kw, flexible_load_kwh, schedule, price_history, simulation_time) do
    # If we don't have enough price history, just use base consumption
    if length(price_history) < 4 do
      {base_consumption_kw, schedule}
    else
      current_hour = simulation_time.hour

      # Check if this hour has scheduled flexible load
      scheduled_load = Map.get(schedule, current_hour, 0.0)

      # Every 6 hours, re-evaluate and reschedule flexible load for next 4 hours
      should_reschedule = rem(current_hour, 6) == 0

      if should_reschedule do
        # Find cheapest hour in next 4 hours based on price trend
        avg_price = calculate_avg_spot_price(price_history)
        current_price = List.first(price_history) || avg_price

        # If current price < average, run flexible load now
        # Otherwise, defer it (assume cheaper later)
        if current_price < avg_price * 0.90 do
          # Run flexible load this hour
          new_schedule = Map.put(%{}, current_hour, flexible_load_kwh)
          consumption = base_consumption_kw + flexible_load_kwh
          {consumption, new_schedule}
        else
          # Defer flexible load
          new_schedule = %{}
          {base_consumption_kw, new_schedule}
        end
      else
        # Use existing schedule
        consumption = base_consumption_kw + scheduled_load
        {consumption, schedule}
      end
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

  defp simulate_battery_and_grid_intelligent(
         current_battery_kwh,
         battery_capacity_kwh,
         net_power_kw,
         elapsed_hours,
         current_spot_price,
         price_history,
         contract,
         simulation_time
       ) do
    # Energy available/needed over the time period
    net_energy_kwh = net_power_kw * elapsed_hours

    # Calculate average spot price for arbitrage decision
    avg_spot_price = calculate_avg_spot_price(price_history)

    # Get current buy/sell prices from contract (or spot if no contract)
    {buy_price, sell_price} = if contract do
      {Contract.buy_price(contract, simulation_time), Contract.sell_price(contract, simulation_time)}
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
end
