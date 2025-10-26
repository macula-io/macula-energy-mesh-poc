defmodule CortexIqUtilities.ProviderBot do
  @moduledoc """
  GenServer representing an energy provider with contract-based pricing.

  Each provider:
  - Publishes contract offers (12-month contracts with day/night pricing)
  - Publishes spot market prices (for customers without contracts)
  - Subscribes to simulation time updates
  - Uses a specific pricing strategy

  Publishes to WAMP topics:
  - energy.hub.provider.{id}.contract_offer
  - energy.hub.provider.{id}.spot_price

  Subscribes to:
  - energy.hub.simulation.time

  ## Pricing Strategies
  - Steady Eddie: Consistent mid-range prices, small discount
  - Night Owl: Cheap at night, expensive during day, big discount
  - Solar Surfer: Cheap during solar peak, expensive at night
  - Peak Predator: High during consumption peaks
  - Discount King: Competitive rates, huge discount, high minimum
  """
  use GenServer
  require Logger

  alias CortexIqCore.{Provider, ContractOffer, SpotPrice, Contract}
  alias MaculaOs.Wamp.Client

  defstruct [
    :provider_id,
    :provider,
    :wamp_client,
    :realm,
    :current_simulation_time,
    :current_market_spot_price,  # Spot price from SpotMarketBroadcaster
    :current_offer,
    :current_spot_price,  # Our provider's spot price for non-contracted customers
    :last_offer_update,
    :last_spot_update,
    active_contracts: %{},  # %{contract_id => contract}
    contracts_by_home: %{}   # %{home_id => contract_id} for quick lookup
  ]

  # Update intervals (real-time milliseconds)
  @contract_offer_update_ms 500  # ~14.6 simulation hours at 105,120x
  @spot_price_update_ms 200      # ~5.8 simulation hours at 105,120x (more frequent)

  ## Client API

  def start_link(opts) do
    provider_id = Keyword.fetch!(opts, :provider_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(provider_id))
  end

  def get_state(provider_id) do
    GenServer.call(via_tuple(provider_id), :get_state)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    provider_id = Keyword.fetch!(opts, :provider_id)
    realm = Keyword.get(opts, :realm, "energy.hub")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    # Get provider metadata from CortexIqCore
    provider = Provider.get(provider_id)

    unless provider do
      {:stop, {:error, "Unknown provider: #{provider_id}"}}
    end

    Logger.info("Starting ProviderBot for #{provider.name} (#{provider_id})")
    Logger.info("  Strategy: #{provider.strategy}")
    Logger.info("  Base day buy price: $#{provider.base_day_buy_price}/kWh")
    Logger.info("  Switching discount: $#{provider.switching_discount}")

    # Connect to WAMP
    {:ok, wamp_client} =
      MaculaOs.Wamp.start_link(
        url: bondy_url,
        realm: realm
      )

    state = %__MODULE__{
      provider_id: provider_id,
      provider: provider,
      wamp_client: wamp_client,
      realm: realm,
      current_simulation_time: nil,
      current_offer: nil,
      current_spot_price: nil,
      last_offer_update: 0,
      last_spot_update: 0
    }

    # Defer subscription until connection is ready
    Process.send_after(self(), :subscribe, 100)

    # Schedule first updates with staggered delays to avoid thundering herd
    Process.send_after(self(), :update_contract_offer, :rand.uniform(@contract_offer_update_ms))
    Process.send_after(self(), :update_spot_price, :rand.uniform(@spot_price_update_ms))

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    # Now that connection should be ready, subscribe to topics and register RPC endpoints
    Logger.info("Provider #{state.provider_id}: Subscribing to WAMP topics and registering RPC endpoints")

    with :ok <- subscribe_to_simulation_time(state.wamp_client),
         :ok <- subscribe_to_market_spot_price(state.wamp_client),
         :ok <- subscribe_to_home_trades(state.wamp_client),
         :ok <- register_accept_offer_rpc(state.wamp_client, state.provider_id) do
      Logger.info("Provider #{state.provider_id}: Subscribed to all topics and registered RPC endpoints")
      {:noreply, state}
    else
      {:error, reason} ->
        Logger.warning("Provider #{state.provider_id}: Failed to subscribe/register: #{inspect(reason)}, retrying...")
        # Retry after a delay
        Process.send_after(self(), :subscribe, 500)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:wamp_event, "be.cortexiq.simulation.time_advanced", _args, kwargs, _details}, state) do
    # Parse simulation time from event
    {:ok, sim_time, _} = DateTime.from_iso8601(kwargs["simulation_time"])

    Logger.debug("Provider #{state.provider_id} received simulation time: #{DateTime.to_time(sim_time)}")

    new_state = %{state | current_simulation_time: sim_time}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_event, "be.cortexiq.market.spot_price_updated", _args, kwargs, _details}, state) do
    # Parse market spot price from event
    spot_price = kwargs["spot_price"]

    Logger.debug("Provider #{state.provider_id} received market spot price: $#{spot_price}/kWh")

    new_state = %{state | current_market_spot_price: spot_price}
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_event, "be.cortexiq.home.traded", _args, kwargs, _details}, state) do
    # Only track trades for this provider's contracts
    if kwargs["provider_id"] == state.provider_id do
      Logger.debug(
        "Provider #{state.provider_id}: Trade - Home #{kwargs["home_id"]} - " <>
          "Import: #{kwargs["grid_import_kwh"]} kWh, Export: #{kwargs["grid_export_kwh"]} kWh, " <>
          "Net cost: $#{kwargs["net_cost"]}"
      )
      # In the future, we could accumulate metrics here
      # For now, we just log and let the dashboard aggregate via Flow
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:update_contract_offer, state) do
    new_state =
      with %DateTime{} = sim_time <- state.current_simulation_time do
        # Decide whether to offer static or dynamic contract
        contract_type = decide_contract_type(state.provider)

        # Calculate pricing based on contract type
        pricing = calculate_contract_pricing(state.provider, contract_type, state.current_market_spot_price, sim_time)

        # Create contract offer
        offer = ContractOffer.new(state.provider_id, pricing, sim_time)

        # Publish contract offer
        publish_contract_offer(state, offer, sim_time)

        # Log based on contract type
        log_contract_offer(state.provider.name, offer)

        %{state | current_offer: offer, last_offer_update: System.monotonic_time(:millisecond)}
      else
        _ ->
          Logger.debug("Provider #{state.provider_id}: No simulation time yet, skipping contract offer update")
          state
      end

    # Schedule next update
    Process.send_after(self(), :update_contract_offer, @contract_offer_update_ms)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_spot_price, state) do
    new_state =
      with %DateTime{} = sim_time <- state.current_simulation_time do
        # Spot prices are more volatile and less favorable than contract prices
        {buy_price, sell_price} = calculate_spot_pricing(state.provider, sim_time)

        # Create spot price
        spot_price = SpotPrice.new(state.provider_id, buy_price, sell_price, sim_time)

        # Publish spot price
        publish_spot_price(state, spot_price, sim_time)

        Logger.debug(
          "💰 #{state.provider.name}: Spot price - Buy: $#{spot_price.buy_price}/kWh, Sell: $#{spot_price.sell_price}/kWh"
        )

        %{state | current_spot_price: spot_price, last_spot_update: System.monotonic_time(:millisecond)}
      else
        _ ->
          Logger.debug("Provider #{state.provider_id}: No simulation time yet, skipping spot price update")
          state
      end

    # Schedule next update
    Process.send_after(self(), :update_spot_price, @spot_price_update_ms)

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:wamp_call, procedure, args, kwargs, invocation_id}, state) do
    # Handle RPC call to accept contract offer
    case procedure do
      "be.cortexiq.provider." <> rest ->
        if String.starts_with?(rest, "#{state.provider_id}.accept_offer") do
          handle_accept_offer_rpc(state, args, kwargs, invocation_id)
        else
          {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  ## Private Functions

  defp via_tuple(provider_id) do
    {:via, Registry, {CortexIqUtilities.Registry, provider_id}}
  end

  defp subscribe_to_simulation_time(wamp_client) do
    topic = "be.cortexiq.simulation.time_advanced"
    Logger.info("Subscribing to #{topic}")

    provider_bot_pid = self()

    handler = fn _topic, event_data ->
      args = Map.get(event_data, :args, [])
      kwargs = Map.get(event_data, :kwargs, %{})
      details = Map.get(event_data, :details, %{})
      send(provider_bot_pid, {:wamp_event, topic, args, kwargs, details})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_market_spot_price(wamp_client) do
    topic = "be.cortexiq.market.spot_price_updated"
    Logger.info("Subscribing to #{topic}")

    provider_bot_pid = self()

    handler = fn _topic, event_data ->
      args = Map.get(event_data, :args, [])
      kwargs = Map.get(event_data, :kwargs, %{})
      details = Map.get(event_data, :details, %{})
      send(provider_bot_pid, {:wamp_event, topic, args, kwargs, details})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp subscribe_to_home_trades(wamp_client) do
    topic = "be.cortexiq.home.traded"
    Logger.info("Subscribing to #{topic}")

    provider_bot_pid = self()

    handler = fn _topic, event_data ->
      args = Map.get(event_data, :args, [])
      kwargs = Map.get(event_data, :kwargs, %{})
      details = Map.get(event_data, :details, %{})
      send(provider_bot_pid, {:wamp_event, topic, args, kwargs, details})
    end

    case Client.subscribe(wamp_client, topic, handler) do
      {:ok, _sub_id} -> :ok
      error -> error
    end
  end

  defp decide_contract_type(provider) do
    case provider.contract_type_mix do
      :all_static -> :static
      :all_dynamic -> :dynamic
      :mixed ->
        # Random selection based on dynamic_percentage
        if :rand.uniform() < provider.dynamic_percentage do
          :dynamic
        else
          :static
        end
    end
  end

  defp calculate_contract_pricing(provider, :static, _market_spot_price, simulation_time) do
    # Static contract with fixed prices
    day_buy = apply_strategy_modifier(provider, simulation_time, provider.base_day_buy_price, :day, :buy)
    night_buy = apply_strategy_modifier(provider, simulation_time, provider.base_night_buy_price, :night, :buy)
    day_sell = apply_strategy_modifier(provider, simulation_time, provider.base_day_sell_price, :day, :sell)
    night_sell = apply_strategy_modifier(provider, simulation_time, provider.base_night_sell_price, :night, :sell)

    %{
      contract_type: :static,
      day_buy_price: Float.round(day_buy, 4),
      night_buy_price: Float.round(night_buy, 4),
      day_sell_price: Float.round(day_sell, 4),
      night_sell_price: Float.round(night_sell, 4),
      switching_discount: provider.switching_discount,
      minimum_monthly_kwh: provider.minimum_monthly_kwh,
      duration_months: 12
    }
  end

  defp calculate_contract_pricing(provider, :dynamic, _market_spot_price, _simulation_time) do
    # Dynamic contract with spot-based pricing
    # Add small variation to markup/markdown to create competition
    buy_markup_variation = provider.buy_markup * (0.95 + :rand.uniform() * 0.10)
    sell_markdown_variation = provider.sell_markdown * (0.95 + :rand.uniform() * 0.10)

    %{
      contract_type: :dynamic,
      buy_markup: Float.round(buy_markup_variation, 4),
      sell_markdown: Float.round(sell_markdown_variation, 4),
      switching_discount: provider.switching_discount,
      minimum_monthly_kwh: provider.minimum_monthly_kwh,
      duration_months: 12
    }
  end

  defp log_contract_offer(provider_name, %{contract_type: :static} = offer) do
    Logger.info(
      "📄 #{provider_name}: Static contract - Day: $#{offer.day_buy_price}/kWh, " <>
        "Night: $#{offer.night_buy_price}/kWh, Discount: $#{offer.switching_discount}"
    )
  end

  defp log_contract_offer(provider_name, %{contract_type: :dynamic} = offer) do
    Logger.info(
      "⚡ #{provider_name}: Dynamic contract - Markup: +$#{offer.buy_markup}/kWh, " <>
        "Markdown: -$#{offer.sell_markdown}/kWh, Discount: $#{offer.switching_discount}"
    )
  end

  defp calculate_spot_pricing(provider, simulation_time) do
    # Spot prices are:
    # - More expensive to buy (20% markup)
    # - Less attractive to sell (20% reduction)
    # - More volatile (±15% random variation)

    hour = simulation_time.hour
    is_day = hour >= 6 and hour < 18

    base_buy =
      if is_day do
        provider.base_day_buy_price * 1.20
      else
        provider.base_night_buy_price * 1.20
      end

    base_sell =
      if is_day do
        provider.base_day_sell_price * 0.80
      else
        provider.base_night_sell_price * 0.80
      end

    # Add volatility
    volatility = 0.85 + :rand.uniform() * 0.30
    # ±15%

    buy_price = Float.round(base_buy * volatility, 4)
    sell_price = Float.round(base_sell * volatility, 4)

    {buy_price, sell_price}
  end

  defp apply_strategy_modifier(provider, _simulation_time, base_price, _period, _type) do
    # For now, just add small random variation (±2%)
    # In a more sophisticated version, we'd adjust based on:
    # - Current market conditions
    # - Provider's market share goals
    # - Competitor pricing
    # - Time of year, day of week, etc.

    case provider.strategy do
      :steady_eddie ->
        # Very stable, minimal variation
        base_price * (0.99 + :rand.uniform() * 0.02)

      :discount_king ->
        # Competitive pricing (5% lower on average)
        base_price * (0.93 + :rand.uniform() * 0.04)

      _ ->
        # Normal variation
        base_price * (0.98 + :rand.uniform() * 0.04)
    end
  end

  defp publish_contract_offer(state, offer, simulation_time) do
    # Publish to single market topic - all providers use same topic
    topic = "be.cortexiq.market.contract_proposed"
    event =
      ContractOffer.to_event(offer, simulation_time)
      |> Map.put(:provider_name, state.provider.name)
      |> Map.put(:strategy, Atom.to_string(state.provider.strategy))

    Logger.info("Provider #{state.provider_id}: Publishing contract offer to #{topic}")
    Client.publish(state.wamp_client, topic, [], event, %{})
    Logger.info("Provider #{state.provider_id}: Contract offer published successfully")
  end

  defp publish_spot_price(state, spot_price, simulation_time) do
    # Publish to single market topic - all providers use same topic
    topic = "be.cortexiq.market.spot_price_updated"
    event =
      SpotPrice.to_event(spot_price, simulation_time)
      |> Map.put(:provider_name, state.provider.name)
      |> Map.put(:strategy, Atom.to_string(state.provider.strategy))

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp register_accept_offer_rpc(wamp_client, provider_id) do
    procedure = "be.cortexiq.provider.#{provider_id}.accept_offer"
    Logger.info("Registering RPC procedure: #{procedure}")

    provider_bot_pid = self()

    # RPC handler - receives calls and sends to GenServer
    handler = fn args, kwargs, invocation_id ->
      send(provider_bot_pid, {:wamp_call, procedure, args, kwargs, invocation_id})
      # Return value will be sent later via Client.yield
      :deferred
    end

    case Client.register(wamp_client, procedure, handler) do
      {:ok, _registration_id} -> :ok
      error -> error
    end
  end

  defp handle_accept_offer_rpc(state, _args, kwargs, invocation_id) do
    # Extract request parameters
    home_id = kwargs["home_id"]
    offer_id = kwargs["offer_id"]
    reason = String.to_existing_atom(kwargs["reason"] || "switch")
    {:ok, simulation_time, _} = DateTime.from_iso8601(kwargs["simulation_time"] || DateTime.to_iso8601(DateTime.utc_now()))

    Logger.info("Provider #{state.provider_id}: Received RPC accept_offer from home #{home_id}, offer #{offer_id}")

    # Validate and process contract signing
    {success, response} = handle_contract_signing_request(state, home_id, offer_id)

    # Send RPC response
    if success do
      contract = response[:contract]

      # Return success to caller
      result = %{
        success: true,
        contract_id: contract.id,
        start_date: DateTime.to_iso8601(contract.start_date),
        end_date: DateTime.to_iso8601(contract.end_date)
      }
      Client.yield(state.wamp_client, invocation_id, [result], %{})

      # Publish contract_confirmed event for dashboard
      publish_contract_confirmed(state, contract, home_id, reason, simulation_time)

      # Update state with new contract
      new_state = %{state |
        active_contracts: Map.put(state.active_contracts, contract.id, contract),
        contracts_by_home: Map.put(state.contracts_by_home, home_id, contract.id)
      }
      {:noreply, new_state}
    else
      # Return error to caller
      result = %{
        success: false,
        reason: response.reason
      }
      Client.yield(state.wamp_client, invocation_id, [result], %{})

      # Also publish rejection event for dashboard/logging
      publish_contract_rejected(state, home_id, offer_id, response.reason)

      {:noreply, state}
    end
  end

  defp handle_contract_signing_request(state, home_id, offer_id) do
    # Validate request
    cond do
      # Check if current offer exists and matches
      state.current_offer == nil ->
        {false, %{success: false, reason: "No active offer available"}}

      state.current_offer.offer_id != offer_id ->
        {false, %{success: false, reason: "Offer expired or invalid"}}

      # Check if home already has contract with us
      Map.has_key?(state.contracts_by_home, home_id) ->
        existing_contract_id = state.contracts_by_home[home_id]
        existing_contract = state.active_contracts[existing_contract_id]

        # Allow renewal if contract is expiring soon (within 30 days)
        if state.current_simulation_time && existing_contract do
          days_remaining = Contract.days_remaining(existing_contract, state.current_simulation_time)

          if days_remaining > 30 do
            {false, %{success: false, reason: "Home already has active contract (expires in #{days_remaining} days)"}}
          else
            # Allow renewal
            create_contract(state, home_id, :renewal)
          end
        else
          {false, %{success: false, reason: "Home already has active contract"}}
        end

      # All validations passed, create contract
      true ->
        create_contract(state, home_id, :new)
    end
  end

  defp create_contract(state, home_id, reason) do
    simulation_time = state.current_simulation_time || DateTime.utc_now()

    # Create contract from current offer
    contract = Contract.from_offer(
      Map.from_struct(state.current_offer),
      home_id,
      simulation_time,
      reason
    )

    Logger.info("Provider #{state.provider_id}: Contract signed with home #{home_id} (#{contract.id})")

    # Publish contract_confirmed event
    publish_contract_confirmed(state, contract, home_id, reason, simulation_time)

    # Return success response with contract details
    {true, %{
      success: true,
      contract_id: contract.id,
      provider_id: state.provider_id,
      start_date: DateTime.to_iso8601(contract.start_date),
      end_date: DateTime.to_iso8601(contract.end_date),
      contract: contract
    }}
  end

  defp publish_contract_confirmed(state, contract, home_id, reason, simulation_time) do
    topic = "be.cortexiq.market.contract_confirmed"

    event = %{
      contract_id: contract.id,
      home_id: home_id,
      provider_id: state.provider_id,
      provider_name: state.provider.name,
      offer_id: contract.offer_id,
      start_date: DateTime.to_iso8601(contract.start_date),
      end_date: DateTime.to_iso8601(contract.end_date),
      reason: Atom.to_string(reason),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})

    Logger.info("Provider #{state.provider_id}: Published contract_confirmed for home #{home_id}")
  end

  defp publish_contract_rejected(state, home_id, offer_id, reason) do
    topic = "be.cortexiq.market.contract_rejected"
    simulation_time = state.current_simulation_time || DateTime.utc_now()

    event = %{
      home_id: home_id,
      provider_id: state.provider_id,
      provider_name: state.provider.name,
      offer_id: offer_id,
      reason: reason,
      simulation_time: DateTime.to_iso8601(simulation_time)
    }

    Client.publish(state.wamp_client, topic, [], event, %{})

    Logger.warning("Provider #{state.provider_id}: Rejected contract request from home #{home_id}: #{reason}")
  end
end
