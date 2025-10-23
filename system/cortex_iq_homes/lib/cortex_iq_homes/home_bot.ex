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
  - energy.hub.home.{id}.production
  - energy.hub.home.{id}.consumption
  - energy.hub.home.{id}.storage
  - energy.hub.home.{id}.balance
  - energy.hub.home.{id}.contract
  - energy.hub.market.contract.signed
  - energy.hub.market.contract.switched
  - energy.hub.market.trade

  Subscribes to:
  - energy.hub.simulation.time
  - energy.hub.provider.*.contract_offer
  - energy.hub.provider.{current_provider}.spot_price (if no contract)
  """

  use GenServer
  require Logger

  alias CortexIqCore.{Home, Contract, ContractOffer, EnergyBalance, SimulationTime}
  alias MaculaOs.Wamp.Client

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
    :last_balance_publish
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
    home_id = Keyword.fetch!(opts, :home_id)
    realm = Keyword.get(opts, :realm, "energy.hub")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    Logger.info("Starting HomeBotNew for #{home_id}")

    # Create home with random location and capacities
    home = Home.new(home_id)

    Logger.info("  Location: #{home.location.city}, #{home.location.postal_code}")
    Logger.info("  Solar capacity: #{Float.round(home.solar_capacity_kw, 1)} kW")
    Logger.info("  Battery capacity: #{Float.round(home.battery_capacity_kwh, 1)} kWh")

    # Connect to WAMP
    {:ok, wamp_client} =
      MaculaOs.Wamp.start_link(
        url: bondy_url,
        realm: realm
      )

    # Initialize battery at 50-80% charge
    initial_battery_kwh = home.battery_capacity_kwh * (0.5 + :rand.uniform() * 0.3)

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
      last_balance_publish: 0
    }

    # Defer subscriptions until after init completes (connection might not be ready yet)
    Process.send_after(self(), :subscribe, 100)

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

    case subscribe_to_simulation_time(state.wamp_client) do
      :ok ->
        Logger.info("Home #{state.home_id}: Subscribed to simulation time")

      {:error, reason} ->
        Logger.warning("Home #{state.home_id}: Failed to subscribe to simulation time: #{inspect(reason)}")
        # Retry after a delay
        Process.send_after(self(), :subscribe, 500)
    end

    case subscribe_to_all_contract_offers(state.wamp_client) do
      :ok ->
        Logger.info("Home #{state.home_id}: Subscribed to contract offers")

      {:error, reason} ->
        Logger.warning("Home #{state.home_id}: Failed to subscribe to contract offers: #{inspect(reason)}")
        # Retry after a delay
        Process.send_after(self(), :subscribe, 500)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:wamp_event, "energy.hub.simulation.time", _args, kwargs, _details}, state) do
    # Parse simulation time from event
    {:ok, sim_time, _} = DateTime.from_iso8601(kwargs["simulation_time"])

    Logger.debug("Home #{state.home_id} received simulation time: #{DateTime.to_time(sim_time)}")

    # Check if this is the first simulation time received
    new_state =
      if state.current_simulation_time == nil do
        # Initialize contract and energy balance on first simulation time
        initialize_contract_and_balance(state, sim_time)
      else
        %{state | current_simulation_time: sim_time}
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_event, topic, _args, kwargs, _details}, state) do
    cond do
      String.contains?(topic, ".contract_offer") ->
        # Provider published a contract offer
        offer = ContractOffer.from_event(kwargs)
        Logger.debug("Home #{state.home_id} received contract offer from #{offer.provider_id}")

        # Store offer
        provider_offers = Map.put(state.provider_offers, offer.provider_id, offer)
        {:noreply, %{state | provider_offers: provider_offers}}

      String.contains?(topic, ".spot_price") ->
        # Provider published spot price (for homes without contracts)
        Logger.debug("Home #{state.home_id} received spot price")
        # TODO: Store spot prices if needed
        {:noreply, state}

      true ->
        Logger.warning("Home #{state.home_id} received unknown event from #{topic}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:update, state) do
    new_state =
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

    # Schedule next update
    Process.send_after(self(), :update, @update_interval_ms)

    {:noreply, new_state}
  end

  ## Private Functions - Subscription

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, home_id}}
  end

  defp subscribe_to_simulation_time(wamp_client) do
    topic = "energy.hub.simulation.time"
    Logger.info("Subscribing to #{topic}")

    # Capture the home bot PID (NOT the WAMP client PID)
    home_bot_pid = self()

    handler = fn _topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    Client.subscribe(wamp_client, topic, handler)
  end

  defp subscribe_to_all_contract_offers(wamp_client) do
    # Subscribe to all provider contract offers using wildcard pattern
    # WAMP wildcard subscription: energy.hub.provider..contract_offer
    topic_pattern = "energy.hub.provider..contract_offer"
    Logger.info("Subscribing to contract offers: #{topic_pattern}")

    # Capture the home bot PID (NOT the WAMP client PID)
    home_bot_pid = self()

    handler = fn topic, event_data ->
      kwargs = Map.get(event_data, :kwargs, %{})
      send(home_bot_pid, {:wamp_event, topic, [], kwargs, %{}})
    end

    # Note: This assumes WAMP broker supports wildcard subscriptions
    # If not, we'll need to subscribe to each provider individually
    Client.subscribe(wamp_client, topic_pattern, handler, %{match: "wildcard"})
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

    %{
      state
      | current_simulation_time: simulation_time,
        current_contract: contract,
        energy_balance: energy_balance
    }
  end

  ## Private Functions - Simulation

  defp simulate_production_and_consumption(state, simulation_time) do
    # Calculate solar production (kW) based on time of day
    production_kw = calculate_solar_production(state.home, simulation_time)

    # Calculate consumption (kW) based on time of day
    consumption_kw = calculate_consumption(state.home, simulation_time)

    # Calculate net power (positive = surplus, negative = deficit)
    net_power_kw = production_kw - consumption_kw

    # Calculate time elapsed since last update (~3 simulation hours)
    # At 105,120x speed, 100ms real-time = 10,512 seconds = ~2.92 hours simulation
    elapsed_hours = 10_512 / 3600.0

    # Update battery and calculate grid transactions
    {new_battery_kwh, buy_kwh, sell_kwh} =
      simulate_battery_and_grid(
        state.battery_state_kwh,
        state.home.battery_capacity_kwh,
        net_power_kw,
        elapsed_hours
      )

    # Record energy transactions in balance
    new_balance =
      state.energy_balance
      |> record_buy_transaction(state.current_contract, buy_kwh, simulation_time)
      |> record_sell_transaction(state.current_contract, sell_kwh, simulation_time)

    # Publish events
    publish_production(state, production_kw * 1000, simulation_time)
    publish_consumption(state, consumption_kw * 1000, simulation_time)
    publish_storage(state, new_battery_kwh, state.home.battery_capacity_kwh, simulation_time)

    if buy_kwh > 0 or sell_kwh > 0 do
      publish_trades(state, buy_kwh, sell_kwh, simulation_time)
    end

    %{state | battery_state_kwh: new_battery_kwh, energy_balance: new_balance, last_update: System.monotonic_time(:millisecond)}
  end

  defp calculate_solar_production(home, simulation_time) do
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

        # Add ±20% randomness for clouds, etc.
        randomness = 0.8 + :rand.uniform() * 0.4
        max(0.0, base_production * randomness)
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

        # Contract expired - automatically switch to best offer
        case find_best_offer(state.provider_offers, state.energy_balance, simulation_time) do
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
      case find_best_offer(state.provider_offers, state.energy_balance, simulation_time) do
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

  defp find_best_offer(provider_offers, _energy_balance, _simulation_time) when map_size(provider_offers) == 0,
    do: nil

  defp find_best_offer(provider_offers, _energy_balance, _simulation_time) do
    # Simple heuristic: pick offer with lowest average buy price
    # In a more sophisticated version, we'd project costs over contract period

    Enum.min_by(provider_offers, fn {_provider_id, offer} ->
      ContractOffer.avg_buy_price(offer)
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

  defp sign_new_contract(state, offer, _provider_id, reason, simulation_time) do
    old_contract = state.current_contract

    # Create new contract
    new_contract = Contract.from_offer(Map.from_struct(offer), state.home_id, simulation_time, reason)

    # Reset energy balance for new contract period
    new_balance = EnergyBalance.new(state.home_id, new_contract.id, simulation_time)

    # Publish contract event
    publish_contract_signed(state, new_contract, reason, simulation_time)

    if reason == :switch and old_contract do
      publish_contract_switched(state, old_contract, new_contract, simulation_time)
    end

    %{state | current_contract: new_contract, energy_balance: new_balance}
  end

  ## Private Functions - Publishing

  defp publish_production(state, watts, simulation_time) do
    topic = "energy.hub.home.#{state.home_id}.production"

    event = %{
      home_id: state.home_id,
      city: state.home.location.city,
      watts: Float.round(watts, 1),
      source: "solar",
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_consumption(state, watts, simulation_time) do
    topic = "energy.hub.home.#{state.home_id}.consumption"

    event = %{
      home_id: state.home_id,
      city: state.home.location.city,
      watts: Float.round(watts, 1),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_storage(state, battery_kwh, capacity_kwh, simulation_time) do
    topic = "energy.hub.home.#{state.home_id}.storage"

    battery_percent = (battery_kwh / capacity_kwh * 100.0) |> Float.round(1)

    state_label =
      cond do
        battery_percent > 95 -> :full
        battery_percent < 5 -> :empty
        true -> :normal
      end

    event = %{
      home_id: state.home_id,
      city: state.home.location.city,
      battery_percent: battery_percent,
      capacity_kwh: Float.round(capacity_kwh, 1),
      state: Atom.to_string(state_label),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

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
    topic = "energy.hub.home.#{state.home_id}.balance"
    event = EnergyBalance.to_event(state.energy_balance, simulation_time)
    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_contract_signed(state, contract, reason, simulation_time) do
    topic = "energy.hub.market.contract.signed"

    event = %{
      contract_id: contract.id,
      home_id: state.home_id,
      provider_id: contract.provider_id,
      offer_id: contract.offer_id,
      start_date: DateTime.to_iso8601(contract.start_date),
      end_date: DateTime.to_iso8601(contract.end_date),
      reason: Atom.to_string(reason),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_contract_switched(state, old_contract, new_contract, simulation_time) do
    topic = "energy.hub.market.contract.switched"

    days_before_expiry = Contract.days_remaining(old_contract, simulation_time)

    event = %{
      home_id: state.home_id,
      from_contract_id: old_contract.id,
      from_provider_id: old_contract.provider_id,
      to_contract_id: new_contract.id,
      to_provider_id: new_contract.provider_id,
      days_before_expiry: days_before_expiry,
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
    topic = "energy.hub.market.trade"

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
end
