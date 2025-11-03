defmodule CortexIqDashboard.QueryClient do
  @moduledoc """
  WAMP RPC client for querying data from cortex_iq_queries service.

  All dashboard data queries go through this module via WAMP RPC calls.
  NO direct database access in the dashboard!

  This module is ONLY for data queries (reads). For simulation control
  commands (reset, pause, resume, set speed), use SimulationClient instead.

  Available procedures:
  - get_overview/0 - Get platform-wide overview data
  - get_homes/1 - Get filtered/sorted homes data
  - get_home/1 - Get single home data
  - get_providers/0 - Get provider data
  - home_exists?/1 - Check if home exists
  - provider_exists?/1 - Check if provider exists
  """
  require Logger

  alias CortexIqDashboard.WampSubscriber

  @doc """
  Get platform-wide overview data.

  Returns:
    {:ok, overview_data} | {:error, reason}

  Example overview_data:
    %{
      total_homes: 50,
      total_energy_bought_kwh: 1234.5,
      total_energy_sold_kwh: 890.2,
      avg_battery_percent: 65.3,
      contract_switches: 15,
      simulation_time: ~U[2025-01-15 14:30:00Z],
      savings_history: [...]
    }
  """
  def get_overview do
    call_procedure("be.cortexiq.energy.queries.get_overview", [], %{})
  end

  @doc """
  Get a single home's data by home_id.

  Parameters:
    - home_id: string - the unique identifier for the home

  Returns:
    {:ok, home_data} | {:error, reason}

  Example home_data:
    %{
      home: %{
        home_id: "home_001",
        name: "Janssens Family",
        iot_provider: "home_connect",
        location: "Brussels",
        street: "Rue de la Loi 123",
        postal_code: "1000",
        region: "brussels",
        latitude: 50.8503,
        longitude: 4.3517,
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0,
        production_kw: 3.5,
        consumption_kw: 1.2,
        battery_percent: 75.0,
        provider_id: "provider_a",
        contract_id: "contract_xyz",
        contract_expires_at: ~U[2026-01-15 00:00:00Z],
        net_balance_kwh: 120.5,
        net_cost: 45.20,
        status: 2
      }
    }
  """
  def get_home(home_id) when is_binary(home_id) do
    call_procedure("be.cortexiq.energy.queries.get_home", [], %{home_id: home_id})
  end

  @doc """
  Get homes data with optional filtering and sorting.

  Parameters:
    - opts: keyword list
      - search: search query string
      - sort_by: :location | :provider | :production | :consumption | :battery | :balance
      - sort_direction: :asc | :desc
      - page: page number (1-indexed)
      - per_page: items per page

  Returns:
    {:ok, homes_data} | {:error, reason}

  Example homes_data:
    %{
      homes: [
        %{
          home_id: "home_001",
          location: "Brussels",
          region: :brussels,
          production_kw: 3.5,
          consumption_kw: 1.2,
          battery_percent: 75.0,
          provider_id: "provider_a",
          contract_end_date: ~U[2026-01-15 00:00:00Z],
          net_balance_kwh: 120.5,
          net_cost: 45.20
        },
        ...
      ],
      total_count: 50,
      page: 1,
      per_page: 25
    }
  """
  def get_homes(opts \\ []) do
    kwargs = %{
      search: Keyword.get(opts, :search, ""),
      sort_by: Keyword.get(opts, :sort_by, "location") |> to_string(),
      sort_direction: Keyword.get(opts, :sort_direction, "asc") |> to_string(),
      page: Keyword.get(opts, :page, 1),
      per_page: Keyword.get(opts, :per_page, 25)
    }

    call_procedure("be.cortexiq.energy.queries.get_homes", [], kwargs)
  end

  @doc """
  Get providers data.

  Returns:
    {:ok, providers_data} | {:error, reason}

  Example providers_data:
    %{
      providers: [
        %{
          provider_id: "provider_a",
          name: "Essent",
          strategy: "steady_eddie",
          market_share: 12,
          active_contracts: 12,
          total_revenue: 1250.50
        },
        ...
      ]
    }
  """
  def get_providers do
    call_procedure("be.cortexiq.energy.queries.get_providers", [], %{})
  end

  @doc """
  Check if a home exists.

  Returns:
    {:ok, true} | {:ok, false} | {:error, reason}
  """
  def home_exists?(home_id) do
    case call_procedure("be.cortexiq.energy.queries.home_exists", [], %{home_id: home_id}) do
      {:ok, %{"exists" => exists}} -> {:ok, exists}
      {:ok, result} -> {:ok, Map.get(result, :exists, false)}
      error -> error
    end
  end

  @doc """
  Check if a provider exists.

  Returns:
    {:ok, true} | {:ok, false} | {:error, reason}
  """
  def provider_exists?(provider_id) do
    case call_procedure("be.cortexiq.energy.queries.provider_exists", [], %{provider_id: provider_id}) do
      {:ok, %{"exists" => exists}} -> {:ok, exists}
      {:ok, result} -> {:ok, Map.get(result, :exists, false)}
      error -> error
    end
  end

  @doc """
  Search for homes by meter EAN or home ID with autocomplete support.

  Parameters:
    - query: search query string
    - limit: maximum number of results (default: 10)

  Returns:
    {:ok, search_results} | {:error, reason}

  Example search_results:
    %{
      homes: [
        %{home_id: "...", meter_ean: "...", name: "...", location: "..."},
        ...
      ]
    }
  """
  def search_homes(query, limit \\ 10) when is_binary(query) do
    call_procedure("be.cortexiq.energy.queries.search_homes", [], %{query: query, limit: limit})
  end

  @doc """
  Get list of all locations with home counts.

  Returns:
    {:ok, locations_data} | {:error, reason}

  Example locations_data:
    %{
      locations: [
        %{location: "Amsterdam", home_count: 15},
        %{location: "Brussels", home_count: 12},
        ...
      ]
    }
  """
  def get_locations do
    call_procedure("be.cortexiq.energy.queries.get_locations", [], %{})
  end

  @doc """
  Get all homes in a specific location.

  Parameters:
    - location: location name (city)

  Returns:
    {:ok, homes_data} | {:error, reason}

  Example homes_data:
    %{
      homes: [
        %{home_id: "...", name: "...", ...},
        ...
      ]
    }
  """
  def get_homes_by_location(location) when is_binary(location) do
    call_procedure("be.cortexiq.energy.queries.get_homes_by_location", [], %{location: location})
  end

  @doc """
  Get historical energy event data for a home (production, consumption, battery).

  Parameters:
    - home_id: unique home identifier
    - hours: number of hours of history to retrieve (default: 24)

  Returns:
    {:ok, history_data} | {:error, reason}

  Example history_data:
    %{
      events: [
        %{
          simulation_time: ~U[2025-01-15 14:00:00.000000Z],
          production_watts: 3500.0,
          consumption_watts: 1200.0,
          battery_percent: 75.0,
          battery_kwh: 7.5,
          battery_state: "charging"
        },
        ...
      ]
    }
  """
  def get_home_history(home_id, hours \\ 24) when is_binary(home_id) do
    call_procedure("be.cortexiq.energy.queries.get_home_history", [], %{home_id: home_id, hours: hours})
  end

  @doc """
  Get historical trade data for a home (grid imports/exports, costs, revenue).

  Parameters:
    - home_id: unique home identifier
    - hours: number of hours of history to retrieve (default: 24)

  Returns:
    {:ok, trades_data} | {:error, reason}

  Example trades_data:
    %{
      trades: [
        %{
          simulation_time: ~U[2025-01-15 14:00:00.000000Z],
          grid_import_kwh: 0.35,
          grid_export_kwh: 0.15,
          import_cost: 0.0525,
          export_revenue: 0.015,
          net_cost: 0.0375,
          provider_id: "provider_a",
          is_day: true
        },
        ...
      ]
    }
  """
  def get_home_trades(home_id, hours \\ 24) when is_binary(home_id) do
    call_procedure("be.cortexiq.energy.queries.get_home_trades", [], %{home_id: home_id, hours: hours})
  end

  # Private Helpers

  defp call_procedure(uri, args, kwargs) do
    # Get WAMP client from WampSubscriber (it manages the connection)
    case GenServer.call(WampSubscriber, :get_wamp_client, 5_000) do
      {:ok, wamp_client} ->
        Logger.debug("QueryClient: Calling RPC #{uri}")

        case MaculaSdk.Wamp.Client.call(wamp_client, uri, args, kwargs, %{}) do
          {:ok, result} ->
            Logger.debug("QueryClient: RPC #{uri} succeeded")

            # WAMP result structure: %{args: [payload], details: %{}, kwargs: %{}, request_id: ...}
            # Extract the actual payload from the args list
            payload = case Map.get(result, :args) do
              [first | _rest] -> first
              [] -> %{}
              other -> other
            end

            {:ok, payload}

          {:error, reason} = error ->
            Logger.error("QueryClient: RPC #{uri} failed: #{inspect(reason)}")
            error
        end

      {:error, :not_connected} ->
        Logger.warning("QueryClient: WAMP client not connected yet")
        {:error, :not_connected}

      {:error, reason} = error ->
        Logger.error("QueryClient: Failed to get WAMP client: #{inspect(reason)}")
        error
    end
  rescue
    error ->
      Logger.error("QueryClient: Exception during RPC call: #{inspect(error)}")
      {:error, :exception}
  end
end
