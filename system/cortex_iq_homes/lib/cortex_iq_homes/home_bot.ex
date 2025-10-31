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
    :home
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

    Logger.info("Starting HomeCoordinator for #{home_id} (#{home.location.city})")

    state = %__MODULE__{
      home_id: home_id,
      home: home
    }

    # Publish home_initialized event after startup
    Process.send_after(self(), :publish_initialized, 1_000)

    {:ok, state}
  end

  ## Message Handlers from Subscribers

  @impl true
  def handle_info(:publish_initialized, state) do
    # Check if home already exists in database before emitting initialized event
    case check_home_exists(state.home_id) do
      {:ok, false} ->
        # Home doesn't exist, emit initialized event
        Logger.info("Home #{state.home_id}: New home, emitting initialized event")
        trigger_publisher(PublishHomeInitialized.Publisher, state.home_id, %{
          home_id: state.home_id,
          city: state.home.location.city,
          solar_capacity_kw: state.home.solar_capacity_kw,
          battery_capacity_kwh: state.home.battery_capacity_kwh,
          postal_code: state.home.location.postal_code
        })

      {:ok, true} ->
        # Home already exists, skip initialization
        Logger.info("Home #{state.home_id}: Already exists, skipping initialized event")

      {:error, reason} ->
        # Error checking, emit anyway to avoid blocking startup
        Logger.warning("Home #{state.home_id}: Failed to check existence (#{inspect(reason)}), emitting initialized event")
        trigger_publisher(PublishHomeInitialized.Publisher, state.home_id, %{
          home_id: state.home_id,
          city: state.home.location.city,
          solar_capacity_kw: state.home.solar_capacity_kw,
          battery_capacity_kwh: state.home.battery_capacity_kwh,
          postal_code: state.home.location.postal_code
        })
    end

    {:noreply, state}
  end

  # From SubscribeSimulationTimeAdvanced.Subscriber
  @impl true
  def handle_info({:time_tick, simulation_time}, state) do
    # Delegate to HomeState for all business logic
    result = HomeState.process_time_tick(state.home_id, simulation_time)

    # Trigger publishers based on result
    trigger_measurement_publisher(state, result.measurements)
    trigger_trade_publishers(state, result.trades)
    trigger_arbitrage_publisher(state, result.arbitrage)
    trigger_balance_publisher(state, result.balance)

    {:noreply, state}
  end

  # From SubscribeContractProposed.Subscriber
  @impl true
  def handle_info({:contract_proposed, provider_id, offer}, state) do
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

  defp check_home_exists(home_id) do
    try do
      case MaculaSdk.Wamp.Pool.call(
             "be.cortexiq.energy.queries.home_exists",
             [],
             %{home_id: home_id},
             %{},
             CortexIqHomes.WampPool
           ) do
        {:ok, _args, %{"exists" => exists}} when is_boolean(exists) ->
          {:ok, exists}

        {:ok, _args, result} ->
          Logger.warning("Unexpected home_exists response: #{inspect(result)}")
          {:error, :unexpected_response}

        {:error, reason} ->
          {:error, reason}
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
    case whereis_publisher(publisher_module, home_id) do
      nil ->
        Logger.warning("Publisher #{inspect(publisher_module)} for #{home_id} not found")

      pid ->
        send(pid, {:publish, data})
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
end
