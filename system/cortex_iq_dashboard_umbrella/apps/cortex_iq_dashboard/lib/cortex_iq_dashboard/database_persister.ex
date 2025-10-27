defmodule CortexIqDashboard.DatabasePersister do
  @moduledoc """
  Subscribes to entity state changes and persists them to the database.

  This follows CQRS write-side pattern:
  - Aggregates maintain in-memory state and broadcast changes
  - DatabasePersister listens to broadcasts and persists to database
  - View queries read from database for initial state
  """
  use GenServer
  require Logger
  alias CortexIqDashboard.DatabaseWriter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Subscribe to entity state changes
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:home")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:provider")

    # Subscribe to initialization events
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:home_initialized")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:provider_initialized")

    Logger.info("DatabasePersister: Started, subscribed to entity state changes and initialization events")
    {:ok, %{persisted_count: 0}}
  end

  @impl true
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    # Persist home state to database (including contract info)
    attrs = %{
      production_kw: home_state.production_kw,
      consumption_kw: home_state.consumption_kw,
      battery_kwh: home_state.battery_kwh,
      battery_percent: home_state.state_of_charge_pct,
      energy_bought_kwh: home_state.energy_bought_kwh,
      energy_sold_kwh: home_state.energy_sold_kwh,
      net_balance_kwh: home_state.net_balance_kwh,
      cost_paid: home_state.cost_paid,
      revenue_received: home_state.revenue_received,
      net_cost: home_state.net_cost,
      provider_id: home_state.provider_id,
      contract_id: home_state.contract_id,
      contract_expires_at: home_state.contract_expires_at,
      updated_at: DateTime.utc_now()
    }

    DatabaseWriter.upsert_home(home_id, attrs)

    new_count = state.persisted_count + 1

    if rem(new_count, 100) == 0 do
      Logger.debug("DatabasePersister: Persisted #{new_count} home state changes")
    end

    {:noreply, %{state | persisted_count: new_count}}
  end

  @impl true
  def handle_info({:provider_state_changed, provider_id, provider_state}, state) do
    # Persist provider state to database
    attrs = %{
      strategy: provider_state.strategy,
      day_buy_price: provider_state.day_buy_price,
      night_buy_price: provider_state.night_buy_price,
      day_sell_price: provider_state.day_sell_price,
      night_sell_price: provider_state.night_sell_price,
      switching_discount: provider_state.switching_discount
    }

    DatabaseWriter.upsert_provider(provider_id, attrs)

    {:noreply, state}
  end

  @impl true
  def handle_info({:home_initialized, kwargs}, state) do
    # Create initial database record for home
    home_id = Map.get(kwargs, "home_id")

    attrs = %{
      home_id: home_id,
      location: Map.get(kwargs, "address"),
      postal_code: Map.get(kwargs, "postal_code"),
      region: Map.get(kwargs, "region"),
      battery_capacity_kwh: Map.get(kwargs, "battery_capacity_kwh", 0.0),
      # Initialize financial tracking fields
      production_kw: 0.0,
      consumption_kw: 0.0,
      battery_percent: 0.0,
      battery_kwh: 0.0,
      energy_bought_kwh: 0.0,
      energy_sold_kwh: 0.0,
      net_balance_kwh: 0.0,
      cost_paid: 0.0,
      revenue_received: 0.0,
      net_cost: 0.0,
      cortexiq_total_commission: 0.0,
      cortexiq_total_savings: 0.0,
      cortexiq_net_savings: 0.0,
      contract_switches_count: 0,
      last_event_at: DateTime.utc_now()
    }

    DatabaseWriter.upsert_home(home_id, attrs)
    Logger.info("DatabasePersister: Created initial record for home #{home_id}")

    {:noreply, state}
  end

  @impl true
  def handle_info({:provider_initialized, kwargs}, state) do
    # Create initial database record for provider
    provider_id = Map.get(kwargs, "provider_id")

    attrs = %{
      provider_id: provider_id,
      provider_name: Map.get(kwargs, "provider_name"),
      strategy: Map.get(kwargs, "strategy"),
      # Initialize metrics
      active_contracts: 0,
      market_share_percent: 0.0,
      day_buy_price: 0.0,
      night_buy_price: 0.0,
      day_sell_price: 0.0,
      night_sell_price: 0.0,
      switching_discount: 0.0,
      last_event_at: DateTime.utc_now()
    }

    DatabaseWriter.upsert_provider(provider_id, attrs)
    Logger.info("DatabasePersister: Created initial record for provider #{provider_id}")

    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
