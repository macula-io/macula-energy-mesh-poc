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

  alias CortexIqCore.{Provider, ContractOffer, SpotPrice}
  alias MaculaOs.Wamp.Client

  defstruct [
    :provider_id,
    :provider,
    :wamp_client,
    :realm,
    :current_simulation_time,
    :current_offer,
    :current_spot_price,
    :last_offer_update,
    :last_spot_update
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
    # Now that connection should be ready, subscribe to simulation time
    Logger.info("Provider #{state.provider_id}: Subscribing to WAMP topics")

    case subscribe_to_simulation_time(state.wamp_client) do
      :ok ->
        Logger.info("Provider #{state.provider_id}: Subscribed to simulation time")

      {:error, reason} ->
        Logger.warning("Provider #{state.provider_id}: Failed to subscribe: #{inspect(reason)}, retrying...")
        # Retry after a delay
        Process.send_after(self(), :subscribe, 500)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:wamp_event, "energy.hub.simulation.time", _args, kwargs, _details}, state) do
    # Parse simulation time from event
    {:ok, sim_time, _} = DateTime.from_iso8601(kwargs["simulation_time"])

    Logger.debug("Provider #{state.provider_id} received simulation time: #{DateTime.to_time(sim_time)}")

    new_state = %{state | current_simulation_time: sim_time}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:update_contract_offer, state) do
    new_state =
      with %DateTime{} = sim_time <- state.current_simulation_time do
        # Calculate current pricing based on strategy and time
        pricing = calculate_contract_pricing(state.provider, sim_time)

        # Create contract offer
        offer = ContractOffer.new(state.provider_id, pricing, sim_time)

        # Publish contract offer
        publish_contract_offer(state, offer, sim_time)

        Logger.info(
          "📄 #{state.provider.name}: Contract offer - Day: $#{offer.day_buy_price}/kWh, " <>
            "Night: $#{offer.night_buy_price}/kWh, Discount: $#{offer.switching_discount}"
        )

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

  ## Private Functions

  defp via_tuple(provider_id) do
    {:via, Registry, {CortexIqUtilities.Registry, provider_id}}
  end

  defp subscribe_to_simulation_time(wamp_client) do
    topic = "energy.hub.simulation.time"
    Logger.info("Subscribing to #{topic}")

    # Capture the provider bot PID (NOT the WAMP client PID)
    provider_bot_pid = self()

    # Handler sends event to provider bot process
    handler = fn _topic, event_data ->
      args = Map.get(event_data, :args, [])
      kwargs = Map.get(event_data, :kwargs, %{})
      details = Map.get(event_data, :details, %{})
      send(provider_bot_pid, {:wamp_event, topic, args, kwargs, details})
    end

    Client.subscribe(wamp_client, topic, handler)
  end

  defp calculate_contract_pricing(provider, simulation_time) do
    # Calculate base pricing with time-based adjustments
    day_buy = apply_strategy_modifier(provider, simulation_time, provider.base_day_buy_price, :day, :buy)
    night_buy = apply_strategy_modifier(provider, simulation_time, provider.base_night_buy_price, :night, :buy)
    day_sell = apply_strategy_modifier(provider, simulation_time, provider.base_day_sell_price, :day, :sell)
    night_sell = apply_strategy_modifier(provider, simulation_time, provider.base_night_sell_price, :night, :sell)

    %{
      day_buy_price: Float.round(day_buy, 4),
      night_buy_price: Float.round(night_buy, 4),
      day_sell_price: Float.round(day_sell, 4),
      night_sell_price: Float.round(night_sell, 4),
      switching_discount: provider.switching_discount,
      minimum_monthly_kwh: provider.minimum_monthly_kwh,
      duration_months: 12
    }
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
    topic = "energy.hub.provider.#{state.provider_id}.contract_offer"
    event =
      ContractOffer.to_event(offer, simulation_time)
      |> Map.put(:provider_name, state.provider.name)
      |> Map.put(:strategy, Atom.to_string(state.provider.strategy))

    Client.publish(state.wamp_client, topic, [], event, %{})
  end

  defp publish_spot_price(state, spot_price, simulation_time) do
    topic = "energy.hub.provider.#{state.provider_id}.spot_price"
    event =
      SpotPrice.to_event(spot_price, simulation_time)
      |> Map.put(:provider_name, state.provider.name)
      |> Map.put(:strategy, Atom.to_string(state.provider.strategy))

    Client.publish(state.wamp_client, topic, [], event, %{})
  end
end
