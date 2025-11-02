defmodule CortexIqQueries.Queries do
  @moduledoc """
  Database queries for dashboard read operations.

  Provides paged queries with filtering and sorting.
  """
  import Ecto.Query
  require Logger

  alias CortexIqQueries.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState}

  @doc """
  Get a single home by home_id.

  ## Parameters
  - home_id: UUID string of the home

  ## Returns
  - home map if found
  - nil if not found
  """
  def get_home(home_id) when is_binary(home_id) do
    case Repo.get(HomeState, home_id) do
      nil -> nil
      home -> serialize_home(home)
    end
  end

  def get_home(_), do: nil

  @doc """
  Get paged list of homes with optional filtering and sorting.

  ## Options
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)
  - region: Filter by region (e.g., "brussels", "flanders")
  - search: Search in home_id, location, postal_code
  - sort_by: Sort field (default: "home_id")
  - sort_direction: "asc" or "desc" (default: "asc")

  ## Returns
  %{
    homes: [%{home_id, location, region, ...}],
    total: total_count,
    page: current_page,
    page_size: items_per_page,
    total_pages: total_pages
  }
  """
  def get_homes(opts \\ %{}) do
    page = max(Map.get(opts, :page, 1), 1)
    page_size = min(max(Map.get(opts, :page_size, 20), 1), 100)
    region = Map.get(opts, :region)
    search = Map.get(opts, :search)
    sort_by = Map.get(opts, :sort_by, "home_id") |> validate_sort_field()
    sort_direction = Map.get(opts, :sort_direction, "asc") |> validate_sort_direction()

    query = from h in HomeState

    # Apply filters
    query =
      if region do
        from h in query, where: h.region == ^region
      else
        query
      end

    query =
      if search && String.trim(search) != "" do
        search_pattern = "%#{search}%"
        from h in query,
          where:
            ilike(h.home_id, ^search_pattern) or
            ilike(h.location, ^search_pattern) or
            ilike(h.postal_code, ^search_pattern)
      else
        query
      end

    # Get total count
    total = Repo.aggregate(query, :count)

    # Apply sorting and pagination
    query =
      query
      |> order_by([h], [{^sort_direction, field(h, ^sort_by)}])
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))

    homes = Repo.all(query)

    total_pages = ceil(total / page_size)

    %{
      homes: Enum.map(homes, &serialize_home/1),
      total: total,
      page: page,
      page_size: page_size,
      total_pages: total_pages
    }
  end

  @doc """
  Get paged list of providers.

  ## Options
  - page: Page number (default: 1)
  - page_size: Items per page (default: 20, max: 100)

  ## Returns
  %{
    providers: [%{provider_id, provider_name, ...}],
    total: total_count,
    page: current_page,
    page_size: items_per_page,
    total_pages: total_pages
  }
  """
  def get_providers(opts \\ %{}) do
    page = max(Map.get(opts, :page, 1), 1)
    page_size = min(max(Map.get(opts, :page_size, 20), 1), 100)

    query = from p in ProviderState

    # Get total count
    total = Repo.aggregate(query, :count)

    # Apply pagination
    query =
      query
      |> order_by([p], asc: p.provider_id)
      |> limit(^page_size)
      |> offset(^((page - 1) * page_size))

    providers = Repo.all(query)

    total_pages = ceil(total / page_size)

    %{
      providers: Enum.map(providers, &serialize_provider/1),
      total: total,
      page: page,
      page_size: page_size,
      total_pages: total_pages
    }
  end

  @doc """
  Get overview/aggregate statistics.

  ## Returns
  %{
    total_homes: count,
    connected_homes_count: count,  # Number of currently connected homes
    total_providers: count,
    total_production_kw: sum,
    total_consumption_kw: sum,
    ...
  }
  """
  def get_overview do
    home_stats =
      from(h in HomeState,
        select: %{
          total_homes: count(h.home_id),
          total_production_kw: sum(h.production_kw),
          total_consumption_kw: sum(h.consumption_kw),
          total_energy_bought_kwh: sum(h.energy_bought_kwh),
          total_energy_sold_kwh: sum(h.energy_sold_kwh),
          total_cost_paid: sum(h.cost_paid),
          total_revenue_received: sum(h.revenue_received),
          cortexiq_total_commission: sum(h.cortexiq_total_commission),
          cortexiq_total_savings: sum(h.cortexiq_total_savings),
          cortexiq_net_savings: sum(h.cortexiq_net_savings),
          total_contract_switches: sum(h.contract_switches_count),
          avg_battery_percent: avg(h.battery_percent)
        }
      )
      |> Repo.one()

    # Get count of currently connected homes
    connected_homes_count =
      from(h in HomeState,
        where: not is_nil(h.connected_at) and is_nil(h.disconnected_at),
        select: count(h.home_id)
      )
      |> Repo.one() || 0

    provider_count = Repo.aggregate(ProviderState, :count)

    %{
      total_homes: home_stats.total_homes || 0,
      connected_homes_count: connected_homes_count,
      total_providers: provider_count || 0,
      total_production_kw: home_stats.total_production_kw || 0.0,
      total_consumption_kw: home_stats.total_consumption_kw || 0.0,
      total_energy_bought_kwh: home_stats.total_energy_bought_kwh || 0.0,
      total_energy_sold_kwh: home_stats.total_energy_sold_kwh || 0.0,
      total_cost_paid: home_stats.total_cost_paid || 0.0,
      total_revenue_received: home_stats.total_revenue_received || 0.0,
      cortexiq_total_commission: home_stats.cortexiq_total_commission || 0.0,
      cortexiq_total_savings: home_stats.cortexiq_total_savings || 0.0,
      cortexiq_net_savings: home_stats.cortexiq_net_savings || 0.0,
      total_contract_switches: home_stats.total_contract_switches || 0,
      avg_battery_percent: home_stats.avg_battery_percent || 0.0
    }
  end

  @doc """
  Check if a home exists in the database.

  ## Parameters
  - home_id: UUID string of the home

  ## Returns
  Boolean - true if home exists, false otherwise
  """
  def home_exists?(home_id) when is_binary(home_id) do
    # Check if home is FULLY initialized (has name and location, not just home_id)
    # This prevents race condition where home.measured creates partial records before home.initialized
    Repo.exists?(from h in HomeState,
      where: h.home_id == ^home_id and not is_nil(h.name) and not is_nil(h.location))
  end

  def home_exists?(_), do: false

  @doc """
  Check if a provider exists in the database.

  ## Parameters
  - provider_id: UUID string of the provider

  ## Returns
  Boolean - true if provider exists, false otherwise
  """
  def provider_exists?(provider_id) when is_binary(provider_id) do
    Repo.exists?(from p in ProviderState, where: p.provider_id == ^provider_id)
  end

  def provider_exists?(_), do: false

  @doc """
  Reserve a home_id in the database.

  Creates a minimal HomeState record with just home_id and status=RESERVED (1).
  This prevents race conditions where multiple homes try to initialize with the same ID.

  ## Parameters
  - home_id: UUID string of the home to reserve

  ## Returns
  - `{:ok, true}` if reservation successful
  - `{:error, :already_exists}` if home_id already reserved/initialized
  - `{:error, reason}` for other errors
  """
  def reserve_home_id(home_id) when is_binary(home_id) do
    # Check if home already exists
    if Repo.exists?(from h in HomeState, where: h.home_id == ^home_id) do
      {:error, :already_exists}
    else
      # Create minimal record with RESERVED status
      # status = 1 (HomeStatus.reserved)
      changeset = HomeState.changeset(%HomeState{}, %{
        home_id: home_id,
        status: 1,  # RESERVED flag
        energy_bought_kwh: 0.0,
        energy_sold_kwh: 0.0,
        net_balance_kwh: 0.0,
        cost_paid: 0.0,
        revenue_received: 0.0,
        net_cost: 0.0,
        cortexiq_total_commission: 0.0,
        cortexiq_total_savings: 0.0,
        cortexiq_net_savings: 0.0,
        contract_switches_count: 0
      })

      case Repo.insert(changeset) do
        {:ok, _home_state} -> {:ok, true}
        {:error, changeset} -> {:error, changeset}
      end
    end
  end

  def reserve_home_id(_), do: {:error, :invalid_home_id}

  @doc """
  Register a home with full seed data in the database.

  Creates a complete HomeState record with all home information including
  name, location, capacities, etc. This is called during home initialization
  to register the complete home profile.

  ## Parameters
  - home_data: Map containing home seed data
    - home_id: UUID string (required)
    - name: Home name (e.g., "Peeters Family")
    - iot_provider: IoT provider name (e.g., "HomeWizard")
    - location: City name
    - street: Street address
    - postal_code: Postal code
    - region: Region identifier
    - latitude: Geographic latitude
    - longitude: Geographic longitude
    - solar_capacity_kw: Solar panel capacity in kW
    - battery_capacity_kwh: Battery storage capacity in kWh

  ## Returns
  - `{:ok, true}` if registration successful
  - `{:error, :already_exists}` if home_id already exists
  - `{:error, reason}` for other errors
  """
  def register_home(home_data) when is_map(home_data) do
    home_id = Map.get(home_data, :home_id)

    unless home_id do
      {:error, :invalid_home_id}
    else
      # Check if home already exists
      if Repo.exists?(from h in HomeState, where: h.home_id == ^home_id) do
        {:error, :already_exists}
      else
        # Create complete record with RESERVED status
        # status = 1 (HomeStatus.reserved)
        changeset = HomeState.changeset(%HomeState{}, %{
          home_id: home_id,
          name: Map.get(home_data, :name),
          iot_provider: Map.get(home_data, :iot_provider),
          location: Map.get(home_data, :location),
          street: Map.get(home_data, :street),
          postal_code: Map.get(home_data, :postal_code),
          region: Map.get(home_data, :region),
          latitude: Map.get(home_data, :latitude),
          longitude: Map.get(home_data, :longitude),
          solar_capacity_kw: Map.get(home_data, :solar_capacity_kw),
          battery_capacity_kwh: Map.get(home_data, :battery_capacity_kwh),
          status: 1,  # RESERVED flag
          energy_bought_kwh: 0.0,
          energy_sold_kwh: 0.0,
          net_balance_kwh: 0.0,
          cost_paid: 0.0,
          revenue_received: 0.0,
          net_cost: 0.0,
          cortexiq_total_commission: 0.0,
          cortexiq_total_savings: 0.0,
          cortexiq_net_savings: 0.0,
          contract_switches_count: 0
        })

        case Repo.insert(changeset) do
          {:ok, _home_state} -> {:ok, true}
          {:error, changeset} -> {:error, changeset}
        end
      end
    end
  end

  def register_home(_), do: {:error, :invalid_home_data}

  # Private helpers

  defp serialize_home(home) do
    %{
      home_id: home.home_id,
      name: home.name,
      iot_provider: home.iot_provider,
      location: home.location,
      street: home.street,
      postal_code: home.postal_code,
      region: home.region,
      latitude: home.latitude,
      longitude: home.longitude,
      solar_capacity_kw: home.solar_capacity_kw,
      production_kw: home.production_kw,
      consumption_kw: home.consumption_kw,
      battery_percent: home.battery_percent,
      battery_capacity_kwh: home.battery_capacity_kwh,
      provider_id: home.provider_id,
      contract_id: home.contract_id,
      energy_bought_kwh: home.energy_bought_kwh,
      energy_sold_kwh: home.energy_sold_kwh,
      net_balance_kwh: home.net_balance_kwh,
      cortexiq_net_savings: home.cortexiq_net_savings,
      status: home.status || 0,
      last_event_at: home.last_event_at
    }
  end

  defp serialize_provider(provider) do
    %{
      provider_id: provider.provider_id,
      provider_name: provider.provider_name,
      strategy: provider.strategy,
      active_contracts: provider.active_contracts,
      market_share_percent: provider.market_share_percent,
      day_buy_price: provider.day_buy_price,
      night_buy_price: provider.night_buy_price,
      day_sell_price: provider.day_sell_price,
      night_sell_price: provider.night_sell_price,
      switching_discount: provider.switching_discount
    }
  end

  defp validate_sort_field(field) when field in ["home_id", "location", "region", "production_kw", "consumption_kw", "battery_percent"],
    do: String.to_existing_atom(field)
  defp validate_sort_field(_), do: :home_id

  defp validate_sort_direction("asc"), do: :asc
  defp validate_sort_direction("desc"), do: :desc
  defp validate_sort_direction(_), do: :asc
end
