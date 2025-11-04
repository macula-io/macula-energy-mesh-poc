defmodule CortexIqHomes.HomeBot do
  @moduledoc """
  Thin coordinator (HomeCoordinator) for a single home's energy management system.

  Architecture (Vertical Slicing):
  - Receives messages from 5 Subscriber systems (each with dedicated WAMP client)
  - Delegates business logic to HomeState GenServer
  - Triggers 10 Publisher systems by sending {:publish, data} messages

  NO direct WAMP interaction - all done via vertical slices!
  NO business logic - all in HomeState!

  This module is PURE ORCHESTRATION:
  1. Subscriber → HomeBot: {:message_type, data}
  2. HomeBot → HomeState: GenServer.call(home_state_pid, {:action, params})
  3. HomeState → HomeBot: %{measurements: ..., trades: ..., ...}
  4. HomeBot → Publishers: send(publisher_pid, {:publish, event_data})
  """

  use GenServer
  require Logger

  alias CortexIqHomes.HomeState
  alias CortexIqHomes.{
    PublishHomeMeasured,
    PublishHomeInitialized,
    PublishHomeConnected,
    PublishHomeDisconnected,
    PublishContractSigned,
    PublishContractSwitched,
    PublishContractExpired,
    PublishTradeExecuted,
    PublishArbitrageProfit,
    PublishBalanceUpdated
  }

  defstruct [
    :home_id,
    :home,
    :last_measurement_ms,  # Timestamp of last published measurement
    :measurement_frequency_ms  # How often to publish measurements (env: MEASUREMENT_FREQUENCY_MS, default: 1000)
  ]

  ## Client API

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  def whereis(home_id) do
    case Registry.lookup(CortexIqHomes.Registry, {__MODULE__, home_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    home = Keyword.fetch!(opts, :home)
    home_id = home.id

    # Read measurement frequency from environment (default: 1000ms = 1/sec)
    measurement_frequency_ms =
      System.get_env("MEASUREMENT_FREQUENCY_MS", "1000")
      |> String.to_integer()

    Logger.info("🏠 Starting HomeCoordinator for #{home_id} (#{home.location.city})")
    Logger.info("  Measurement frequency: #{measurement_frequency_ms}ms (#{1000 / measurement_frequency_ms} measurements/sec)")

    # Subscribe to PubSub for simulation time ticks
    Logger.info("🔌 Home #{home_id}: Subscribing to PubSub channel 'homes:simulation_time_tick'...")
    result = Phoenix.PubSub.subscribe(CortexIqHomes.PubSub, "homes:simulation_time_tick")
    Logger.info("  PubSub.subscribe result: #{inspect(result)}")

    if result == :ok do
      Logger.info("✅ Home #{home_id}: Successfully subscribed to PubSub channel")
    else
      Logger.error("❌ Home #{home_id}: Failed to subscribe to PubSub: #{inspect(result)}")
    end

    state = %__MODULE__{
      home_id: home_id,
      home: home,
      last_measurement_ms: 0,  # Initialize to 0 to publish first measurement immediately
      measurement_frequency_ms: measurement_frequency_ms
    }

    # Publish home_initialized event after startup
    Logger.debug("Home #{home_id}: Scheduling :publish_initialized message in 1000ms")
    Process.send_after(self(), :publish_initialized, 1_000)

    # Schedule random disconnections "now and then" (every 5-15 minutes)
    schedule_random_disconnect()

    {:ok, state}
  end

  ## Message Handlers from Subscribers

  @impl true
  def handle_info(:publish_initialized, state) do
    Logger.info("Home #{state.home_id}: Received :publish_initialized message, registering home...")

    # Register complete home data in database before emitting initialized event
    home_data = %{
      home_id: state.home_id,
      name: state.home.name,
      iot_provider: state.home.iot_provider,
      meter_ean: state.home.meter_ean,
      location: state.home.location.city,
      street: state.home.location.street,
      postal_code: state.home.location.postal_code,
      region: state.home.location.region,
      latitude: state.home.location.latitude,
      longitude: state.home.location.longitude,
      solar_capacity_kw: state.home.solar_capacity_kw,
      battery_capacity_kwh: state.home.battery_capacity_kwh
    }

    case register_home(home_data) do
      {:ok, true} ->
        # Registration successful, emit initialized event
        Logger.info("Home #{state.home_id}: Home registered successfully, emitting initialized event")

        event_data = %{
          home_id: state.home_id,
          name: state.home.name,
          iot_provider: state.home.iot_provider,
          meter_ean: state.home.meter_ean,
          location: state.home.location.city,
          postal_code: state.home.location.postal_code,
          region: state.home.location.region,
          solar_capacity_kw: state.home.solar_capacity_kw,
          battery_capacity_kwh: state.home.battery_capacity_kwh,
          simulation_time: nil
        }

        Logger.debug("Home #{state.home_id}: Triggering publisher with data: #{inspect(event_data)}")
        trigger_publisher(PublishHomeInitialized.Publisher, state.home_id, event_data)
        Logger.info("Home #{state.home_id}: ✓ Initialized event triggered")

        # Schedule home.connected event shortly after initialization
        Process.send_after(self(), :publish_connected, 500)

      {:error, :already_exists} ->
        # Home already exists, skip initialization but emit connected event
        Logger.info("Home #{state.home_id}: Home already registered, skipping initialized event")
        Process.send_after(self(), :publish_connected, 500)

      {:error, reason} ->
        # Error during registration, DO NOT emit event to avoid race conditions
        Logger.error("Home #{state.home_id}: Failed to register home (#{inspect(reason)}), SKIPPING initialized event to prevent data corruption")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_connected, state) do
    Logger.info("Home #{state.home_id}: Emitting home.connected event")

    event_data = %{
      home_id: state.home_id,
      simulation_time: nil
    }

    trigger_publisher(PublishHomeConnected.Publisher, state.home_id, event_data)
    {:noreply, state}
  end

  @impl true
  def handle_info(:random_disconnect, state) do
    Logger.info("Home #{state.home_id}: Random disconnect event - emitting home.disconnected")

    event_data = %{
      home_id: state.home_id,
      simulation_time: nil,
      reason: "random_disconnect"
    }

    trigger_publisher(PublishHomeDisconnected.Publisher, state.home_id, event_data)

    # Schedule reconnection after 10-30 seconds
    reconnect_delay = :rand.uniform(20_000) + 10_000
    Process.send_after(self(), :reconnect, reconnect_delay)

    {:noreply, state}
  end

  @impl true
  def handle_info(:reconnect, state) do
    Logger.info("Home #{state.home_id}: Reconnecting - emitting home.connected")

    event_data = %{
      home_id: state.home_id,
      simulation_time: nil
    }

    trigger_publisher(PublishHomeConnected.Publisher, state.home_id, event_data)

    # Schedule next random disconnect
    schedule_random_disconnect()

    {:noreply, state}
  end

  # From SubscribeSimulationTimeAdvanced.Subscriber
  @impl true
  def handle_info({:simulation_time_tick, simulation_time}, state) do
    Logger.debug("⏰ Home #{state.home_id}: Received :simulation_time_tick from PubSub")
    Logger.debug("  simulation_time: #{inspect(simulation_time)}")

    # Check if enough time has elapsed since last measurement
    now_ms = System.monotonic_time(:millisecond)
    elapsed_ms = now_ms - state.last_measurement_ms
    should_publish_measurement = elapsed_ms >= state.measurement_frequency_ms

    Logger.debug("  elapsed=#{elapsed_ms}ms, freq=#{state.measurement_frequency_ms}ms, should_publish=#{should_publish_measurement}")

    # Delegate to HomeState for all business logic
    result = HomeState.process_time_tick(state.home_id, simulation_time)

    Logger.debug("  result - measurements=#{if result.measurements, do: "present", else: "nil"}")

    # Trigger publishers based on result
    # Only publish measurements if enough time has elapsed (throttling)
    if should_publish_measurement do
      Logger.info("Home #{state.home_id}: ✅ Publishing measurement (elapsed #{elapsed_ms}ms >= #{state.measurement_frequency_ms}ms)")
      trigger_measurement_publisher(state, result.measurements)
    else
      Logger.debug("Home #{state.home_id}: ⏸ Skipping measurement (elapsed #{elapsed_ms}ms < #{state.measurement_frequency_ms}ms)")
    end

    # Always publish trades, arbitrage, and balance (not throttled)
    trigger_trade_publishers(state, result.trades)
    trigger_arbitrage_publisher(state, result.arbitrage)
    trigger_balance_publisher(state, result.balance)

    # Update last measurement timestamp if we published
    new_state =
      if should_publish_measurement do
        %{state | last_measurement_ms: now_ms}
      else
        state
      end

    {:noreply, new_state}
  end

  # From SubscribeContractProposed.Subscriber
  @impl true
  def handle_info({:contract_offer, offer}, state) do
    # Extract provider_id from offer struct
    provider_id = offer.provider_id
    HomeState.store_offer(state.home_id, provider_id, offer)
    {:noreply, state}
  end

  # From SubscribeSpotPriceUpdated.Subscriber
  @impl true
  def handle_info({:spot_price_update, spot_price}, state) do
    HomeState.update_spot_price(state.home_id, spot_price)
    {:noreply, state}
  end

  # From SubscribeContractConfirmed.Subscriber
  @impl true
  def handle_info({:contract_confirmed, contract_id, provider_id, start_date, end_date, reason}, state) do
    result = HomeState.confirm_contract(state.home_id, contract_id, provider_id, start_date, end_date, reason)

    # Trigger contract event publishers
    if reason == :switch do
      trigger_publisher(PublishContractSwitched.Publisher, state.home_id, result.switch_event)
    else
      trigger_publisher(PublishContractSigned.Publisher, state.home_id, result.signed_event)
    end

    {:noreply, state}
  end

  # From SubscribeContractRejected.Subscriber
  @impl true
  def handle_info({:contract_rejected, _provider_id, _reason}, state) do
    # Just log, no action needed
    Logger.debug("Home #{state.home_id}: Contract proposal rejected")
    {:noreply, state}
  end

  @impl true
  def handle_info(message, state) do
    Logger.warning("HomeCoordinator #{state.home_id}: Unexpected message: #{inspect(message)}")
    {:noreply, state}
  end

  ## Helper Functions

  defp register_home(home_data) do
    try do
      case MaculaSdk.Wamp.Pool.call(
             "be.cortexiq.energy.projections.register_home",
             [],
             home_data,
             %{},
             CortexIqHomes.WampPool
           ) do
        # Success: home registered
        {:ok, %{args: [%{"registered" => true}]}} ->
          {:ok, true}

        # Error: home already exists
        {:error, "wamp.error.already_exists"} ->
          {:error, :already_exists}

        # Generic error
        {:error, reason} ->
          {:error, reason}

        # Unexpected response format
        {:ok, response} ->
          Logger.warning("Unexpected register_home response: #{inspect(response)}")
          {:error, :unexpected_response}
      end
    catch
      :exit, reason ->
        Logger.warning("WAMP pool unavailable: #{inspect(reason)}")
        {:error, :pool_unavailable}
    end
  end

  ## Publisher Triggering

  defp trigger_measurement_publisher(_state, nil), do: :ok

  defp trigger_measurement_publisher(state, measurement_data) do
    trigger_publisher(PublishHomeMeasured.Publisher, state.home_id, measurement_data)
  end

  defp trigger_trade_publishers(_state, []), do: :ok

  defp trigger_trade_publishers(state, trades) when is_list(trades) do
    Enum.each(trades, fn trade ->
      trigger_publisher(PublishTradeExecuted.Publisher, state.home_id, trade)
    end)
  end

  defp trigger_arbitrage_publisher(_state, nil), do: :ok
  defp trigger_arbitrage_publisher(_state, profit) when profit <= 0.01, do: :ok

  defp trigger_arbitrage_publisher(state, arbitrage_data) do
    trigger_publisher(PublishArbitrageProfit.Publisher, state.home_id, arbitrage_data)
  end

  defp trigger_balance_publisher(_state, nil), do: :ok

  defp trigger_balance_publisher(state, balance_data) do
    trigger_publisher(PublishBalanceUpdated.Publisher, state.home_id, balance_data)
  end

  defp trigger_publisher(publisher_module, home_id, data) do
    Logger.debug("Home #{home_id}: Looking up publisher #{inspect(publisher_module)}...")

    case whereis_publisher(publisher_module, home_id) do
      nil ->
        Logger.warning("Home #{home_id}: ❌ Publisher #{inspect(publisher_module)} NOT FOUND in registry")

      pid ->
        Logger.debug("Home #{home_id}: ✓ Found publisher #{inspect(publisher_module)} at #{inspect(pid)}, sending {:publish, ...}")
        send(pid, {:publish, data})
        Logger.debug("Home #{home_id}: ✓ Message sent to publisher #{inspect(publisher_module)}")
    end
  end

  defp whereis_publisher(publisher_module, home_id) do
    case Registry.lookup(CortexIqHomes.Registry, {publisher_module, home_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end

  # Schedule a random disconnect "now and then" (every 5-15 minutes)
  defp schedule_random_disconnect do
    # Random delay between 5-15 minutes (300_000 - 900_000 ms)
    disconnect_delay = :rand.uniform(600_000) + 300_000
    Process.send_after(self(), :random_disconnect, disconnect_delay)
  end
end
