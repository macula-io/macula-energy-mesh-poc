defmodule CortexIqProjections.CalculateCityTotals.Aggregator do
  @moduledoc """
  Maintains in-memory city-level aggregates and publishes city.measured events every 5 seconds.

  ## State Structure

  %{
    wamp_client: :wamp_calculate_city_totals,
    cities: %{
      "Breda" => %{
        total_production_kw: 45.3,
        total_consumption_kw: 32.1,
        battery_percents: [75.3, 80.0, 65.5], # For averaging
        home_count: 7,
        last_updated: ~U[2025-01-01 12:00:00Z]
      },
      "Gent" => %{...},
      ...
    }
  }

  ## Aggregation Logic

  - Receives home.measured events from Subscriber
  - Groups by location (city name)
  - Accumulates: production, consumption, battery levels
  - Every 5 seconds, publishes city.measured events for all cities
  - Clears stale city data (no updates in 60 seconds)
  """
  use GenServer
  require Logger
  alias MaculaSdk.Wamp.Client

  @publish_interval_ms 5_000  # 5 seconds
  @stale_threshold_ms 60_000  # 60 seconds

  defmodule State do
    @moduledoc false
    defstruct [:wamp_client, :cities]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Called by Subscriber to update city aggregates with new home measurement data.
  """
  def update_home_measurement(event_data) do
    GenServer.cast(__MODULE__, {:update_home, event_data})
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    state = %State{
      wamp_client: wamp_client,
      cities: %{}
    }

    # Schedule first publish
    schedule_publish()

    Logger.info("CalculateCityTotals.Aggregator: Started")

    {:ok, state}
  end

  @impl true
  def handle_cast({:update_home, event_data}, state) do
    # Extract data from kwargs (WAMP event structure)
    kwargs = Map.get(event_data, :kwargs, %{})
    city_name = Map.get(kwargs, "city")

    Logger.debug("CalculateCityTotals.Aggregator: Received update for city=#{inspect(city_name)}")

    # Skip if no city
    state = if city_name && city_name != "" do
      update_city_aggregate(state, city_name, kwargs)
    else
      Logger.debug("CalculateCityTotals.Aggregator: Skipping - no city name")
      state
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(:publish_city_totals, state) do
    Logger.info("CalculateCityTotals.Aggregator: Timer fired, publishing cities...")

    # Publish city.measured events for all cities
    state = publish_all_cities(state)

    # Remove stale cities (no updates in 60 seconds)
    state = remove_stale_cities(state)

    # Schedule next publish
    schedule_publish()

    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("CalculateCityTotals.Aggregator: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private Functions

  defp schedule_publish do
    Process.send_after(self(), :publish_city_totals, @publish_interval_ms)
  end

  defp update_city_aggregate(state, city_name, kwargs) do
    now = DateTime.utc_now()

    # Extract measurement data from kwargs (using _production_w and _consumption_w)
    production_w = Map.get(kwargs, "_production_w", 0.0) || 0.0
    consumption_w = Map.get(kwargs, "_consumption_w", 0.0) || 0.0
    battery_percent = Map.get(kwargs, "state_of_charge_pct")

    # Convert watts to kilowatts
    production_kw = production_w / 1000.0
    consumption_kw = consumption_w / 1000.0

    # Get existing city data or create new
    city_data = Map.get(state.cities, city_name, %{
      total_production_kw: 0.0,
      total_consumption_kw: 0.0,
      battery_percents: [],
      home_count: 0,
      last_updated: now
    })

    # Update city aggregate
    updated_city_data = %{
      total_production_kw: city_data.total_production_kw + production_kw,
      total_consumption_kw: city_data.total_consumption_kw + consumption_kw,
      battery_percents: if(battery_percent, do: [battery_percent | city_data.battery_percents], else: city_data.battery_percents),
      home_count: city_data.home_count + 1,
      last_updated: now
    }

    updated_cities = Map.put(state.cities, city_name, updated_city_data)
    %{state | cities: updated_cities}
  end

  defp publish_all_cities(%{wamp_client: wamp_client, cities: cities} = state) do
    if Enum.empty?(cities) do
      Logger.debug("CalculateCityTotals.Aggregator: No cities to publish")
      state
    else
      now = DateTime.utc_now()

      Enum.each(cities, fn {city_name, city_data} ->
        publish_city_measured(wamp_client, city_name, city_data, now)
      end)

      Logger.info("CalculateCityTotals.Aggregator: Published city.measured for #{map_size(cities)} cities")

      # Reset aggregates for next interval
      %{state | cities: %{}}
    end
  end

  defp publish_city_measured(wamp_client, city_name, city_data, timestamp) do
    average_battery_percent =
      if Enum.empty?(city_data.battery_percents) do
        nil
      else
        Enum.sum(city_data.battery_percents) / length(city_data.battery_percents)
      end

    net_balance_kw = city_data.total_production_kw - city_data.total_consumption_kw

    payload = %{
      "city_name" => city_name,
      "total_homes" => city_data.home_count,
      "total_production_kw" => Float.round(city_data.total_production_kw, 2),
      "total_consumption_kw" => Float.round(city_data.total_consumption_kw, 2),
      "average_battery_percent" => if(average_battery_percent, do: Float.round(average_battery_percent, 1), else: nil),
      "net_balance_kw" => Float.round(net_balance_kw, 2),
      "timestamp" => DateTime.to_iso8601(timestamp)
    }

    topic = "be.cortexiq.city.measured"

    case Client.publish(wamp_client, topic, [payload], %{}) do
      :ok ->
        Logger.debug("CalculateCityTotals.Aggregator: Published city.measured for #{city_name}")

      {:ok, _publication_id} ->
        Logger.debug("CalculateCityTotals.Aggregator: Published city.measured for #{city_name}")

      {:error, reason} ->
        Logger.error("CalculateCityTotals.Aggregator: Failed to publish city.measured for #{city_name}: #{inspect(reason)}")
    end
  end

  defp remove_stale_cities(%{cities: cities} = state) do
    now = DateTime.utc_now()

    fresh_cities = Enum.filter(cities, fn {_city_name, city_data} ->
      age_ms = DateTime.diff(now, city_data.last_updated, :millisecond)
      age_ms < @stale_threshold_ms
    end)
    |> Map.new()

    removed_count = map_size(cities) - map_size(fresh_cities)

    if removed_count > 0 do
      Logger.info("CalculateCityTotals.Aggregator: Removed #{removed_count} stale cities")
    end

    %{state | cities: fresh_cities}
  end
end
