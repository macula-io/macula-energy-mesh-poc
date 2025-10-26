defmodule CortexIqDashboard.DatabaseWriter do
  @moduledoc """
  Pure database I/O worker - NO business logic.

  Accepts upsert/update commands and executes them asynchronously.
  All business logic lives in the aggregators.
  """
  use GenServer
  require Logger
  import Ecto.Query
  alias CortexIqDashboard.Repo
  alias CortexIqDashboard.Schemas.{HomeState, ProviderState, SystemStats}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Client API - all async casts

  def upsert_home(home_id, attrs) do
    GenServer.cast(__MODULE__, {:upsert_home, home_id, attrs})
  end

  def upsert_provider(provider_id, attrs) do
    GenServer.cast(__MODULE__, {:upsert_provider, provider_id, attrs})
  end

  def update_system_stats(attrs) do
    GenServer.cast(__MODULE__, {:update_system_stats, attrs})
  end

  def increment_contract_switches do
    GenServer.cast(__MODULE__, :increment_contract_switches)
  end

  def recalculate_market_shares do
    GenServer.cast(__MODULE__, :recalculate_market_shares)
  end

  def recalculate_system_aggregates do
    GenServer.cast(__MODULE__, :recalculate_system_aggregates)
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Logger.info("DatabaseWriter: Started")
    {:ok, %{writes_processed: 0}}
  end

  @impl true
  def handle_cast({:upsert_home, home_id, attrs}, state) do
    # Ensure home exists first
    location = CortexIqCore.Geography.location_for_home(home_id)

    Repo.insert!(
      %HomeState{
        home_id: home_id,
        location: location.city,
        postal_code: location.postal_code,
        region: to_string(location.region)
      },
      on_conflict: :nothing,
      conflict_target: :home_id
    )

    # Update with provided attributes
    from(h in HomeState, where: h.home_id == ^home_id)
    |> Repo.update_all(set: Map.to_list(attrs))

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end

  @impl true
  def handle_cast({:upsert_provider, provider_id, attrs}, state) do
    attrs_with_timestamps =
      attrs
      |> Map.put(:provider_id, provider_id)
      |> Map.put(:updated_at, DateTime.utc_now())

    Repo.insert!(
      struct(ProviderState, attrs_with_timestamps),
      on_conflict: [set: Map.to_list(attrs_with_timestamps)],
      conflict_target: :provider_id
    )

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end

  @impl true
  def handle_cast({:update_system_stats, attrs}, state) do
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(set: Map.to_list(attrs))

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end

  @impl true
  def handle_cast(:increment_contract_switches, state) do
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(inc: [contract_switches_count: 1])

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end

  @impl true
  def handle_cast(:recalculate_market_shares, state) do
    # Count contracts per provider
    contract_counts =
      from(h in HomeState,
        where: not is_nil(h.provider_id),
        group_by: h.provider_id,
        select: {h.provider_id, count(h.home_id)}
      )
      |> Repo.all()
      |> Map.new()

    total_contracts = Enum.sum(Map.values(contract_counts))

    # Update each provider's market share
    Enum.each(contract_counts, fn {provider_id, count} ->
      share_percent = if total_contracts > 0, do: count / total_contracts * 100, else: 0.0

      from(p in ProviderState, where: p.provider_id == ^provider_id)
      |> Repo.update_all(
        set: [
          active_contracts: count,
          market_share_percent: share_percent
        ]
      )
    end)

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end

  @impl true
  def handle_cast(:recalculate_system_aggregates, state) do
    # Aggregate all home data
    home_aggregates =
      from(h in HomeState,
        select: %{
          count: count(h.home_id),
          total_production: sum(coalesce(h.production_kw, 0.0)),
          total_consumption: sum(coalesce(h.consumption_kw, 0.0)),
          total_bought: sum(coalesce(h.energy_bought_kwh, 0.0)),
          total_sold: sum(coalesce(h.energy_sold_kwh, 0.0)),
          total_cost: sum(coalesce(h.cost_paid, 0.0)),
          total_revenue: sum(coalesce(h.revenue_received, 0.0)),
          avg_battery: avg(coalesce(h.battery_percent, 0.0))
        }
      )
      |> Repo.one()

    # Count providers
    provider_count = from(p in ProviderState, select: count(p.provider_id)) |> Repo.one()

    # Update system stats
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(
      set: [
        total_homes: home_aggregates.count || 0,
        total_providers: provider_count || 0,
        total_production_kwh: home_aggregates.total_production || 0.0,
        total_consumption_kwh: home_aggregates.total_consumption || 0.0,
        total_energy_bought_kwh: home_aggregates.total_bought || 0.0,
        total_energy_sold_kwh: home_aggregates.total_sold || 0.0,
        total_cost_paid: home_aggregates.total_cost || 0.0,
        total_revenue_received: home_aggregates.total_revenue || 0.0,
        avg_battery_percent: home_aggregates.avg_battery || 0.0,
        updated_at: DateTime.utc_now()
      ]
    )

    {:noreply, %{state | writes_processed: state.writes_processed + 1}}
  end
end
