defmodule CortexIqProjections.CalculateSystemTotals.Aggregator do
  @moduledoc """
  Calculates system-wide totals by aggregating home measurements.

  Subscribes to home.measured events, maintains in-memory state,
  and periodically calculates + publishes totals.

  ## Architecture

  home.measured → In-memory aggregation → Calculate totals (every 500ms)
  → Publish projections.totals_calculated → Store in DB

  ## Why this approach?

  - Dashboard doesn't need to calculate anything
  - Database gets real calculated totals (not stale)
  - Totals are a projection (calculation from events)
  - Follows CQRS: projections own the read model
  """
  use GenServer
  require Logger

  defstruct [
    wamp_client: nil,
    subscribed: false,  # Track if we successfully subscribed
    homes: %{},  # %{home_id => %{production_kw, consumption_kw, battery_percent}}
    last_totals: nil,  # Last calculated totals
    calc_timer: nil,  # Timer for periodic calculation
    history_timer: nil  # Timer for history event emission
  ]

  @calc_interval_ms 500  # Calculate totals every 500ms
  @history_interval_ms 2_000  # Emit history events every 2 seconds

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    # Subscribe to home events to track connection state and measurements
    Process.send_after(self(), :subscribe_home_events, 2000)

    # Start periodic totals calculation (500ms for database updates)
    calc_timer = Process.send_after(self(), :calculate_totals, @calc_interval_ms)

    # Start periodic history emission (2 seconds for dashboard charts)
    history_timer = Process.send_after(self(), :emit_history, @history_interval_ms)

    Logger.info("CalculateSystemTotals.Aggregator started")
    Logger.info("  Calculation interval: #{@calc_interval_ms}ms")
    Logger.info("  History emission interval: #{@history_interval_ms}ms")

    {:ok, %__MODULE__{
      wamp_client: wamp_client,
      calc_timer: calc_timer,
      history_timer: history_timer
    }}
  end

  @impl true
  def handle_info(:subscribe_home_events, state) do
    Logger.info("#{__MODULE__}: Subscribing to home events (connected, disconnected, measured)")

    subscriber_pid = self()

    # Subscribe to home.connected events
    connected_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_connected_event, event_data})
    end

    # Subscribe to home.disconnected events
    disconnected_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_disconnected_event, event_data})
    end

    # Subscribe to home.measured events
    measured_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_measured_event, event_data})
    end

    # Attempt all three subscriptions
    results = [
      {:connected, MaculaSdk.Wamp.Client.subscribe(state.wamp_client, "be.cortexiq.home.connected", connected_handler)},
      {:disconnected, MaculaSdk.Wamp.Client.subscribe(state.wamp_client, "be.cortexiq.home.disconnected", disconnected_handler)},
      {:measured, MaculaSdk.Wamp.Client.subscribe(state.wamp_client, "be.cortexiq.home.measured", measured_handler)}
    ]

    # Check if all succeeded
    all_ok = Enum.all?(results, fn {_event, result} -> result == :ok end)

    case all_ok do
      true ->
        Logger.info("#{__MODULE__}: ✅ Successfully subscribed to all home events (connected, disconnected, measured)")
        {:noreply, %{state | subscribed: true}}

      false ->
        # Find which one failed
        failures = Enum.filter(results, fn {_event, result} -> result != :ok end)
        Logger.error("#{__MODULE__}: Failed to subscribe to some events: #{inspect(failures)}, retrying in 5s...")
        Process.send_after(self(), :subscribe_home_events, 5000)
        {:noreply, state}
    end
  rescue
    e ->
      Logger.error("#{__MODULE__}: Exception during subscribe: #{inspect(e)}, retrying in 5s...")
      Process.send_after(self(), :subscribe_home_events, 5000)
      {:noreply, state}
  end

  @impl true
  def handle_info({:home_connected_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      # Add home to in-memory map with initial zero values
      # If already exists (reconnection), preserve existing state
      home_state = Map.get(state.homes, home_id, %{
        production_kw: 0.0,
        consumption_kw: 0.0,
        battery_percent: 0.0
      })

      new_homes = Map.put(state.homes, home_id, home_state)
      Logger.info("#{__MODULE__}: Home #{home_id} connected - in-memory count now #{map_size(new_homes)}")
      {:noreply, %{state | homes: new_homes}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:home_disconnected_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      # Remove home from in-memory map
      new_homes = Map.delete(state.homes, home_id)
      Logger.info("#{__MODULE__}: Home #{home_id} disconnected - in-memory count now #{map_size(new_homes)}")
      {:noreply, %{state | homes: new_homes}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:home_measured_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")
    production_w = Map.get(kwargs, "_production_w", 0.0)
    consumption_w = Map.get(kwargs, "_consumption_w", 0.0)
    battery_percent = Map.get(kwargs, "state_of_charge_pct", 0.0)

    # Only update if home is already in map (connected)
    # This ensures measurements don't add homes - only home.connected does that
    if home_id && Map.has_key?(state.homes, home_id) do
      # Update in-memory home state
      home_state = %{
        production_kw: production_w / 1000.0,
        consumption_kw: consumption_w / 1000.0,
        battery_percent: battery_percent
      }

      new_homes = Map.put(state.homes, home_id, home_state)
      {:noreply, %{state | homes: new_homes}}
    else
      # Home not in map (either disconnected or never connected)
      # Silently ignore the measurement
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:calculate_totals, state) do
    # Calculate aggregated totals from all homes
    totals = calculate_totals_from_homes(state.homes)

    # Debug logging to see individual battery values
    if map_size(state.homes) > 0 do
      battery_values = state.homes
        |> Map.values()
        |> Enum.map(& &1.battery_percent)
        |> Enum.take(5)  # Show first 5 homes as sample

      Logger.info("#{__MODULE__}: Sample battery values: #{inspect(battery_values)}, avg=#{Float.round(totals.avg_battery_percent, 1)}%")
    end

    # Query currently connected homes from database (connected_at set, disconnected_at null)
    # This matches the in-memory count and avoids showing stale historical data
    import Ecto.Query
    alias CortexIqProjections.Repo
    alias CortexIqDashboardSchemas.Projections.HomeState

    connected_homes_query = from h in HomeState,
      where: not is_nil(h.connected_at) and is_nil(h.disconnected_at)
    total_homes_in_db = Repo.aggregate(connected_homes_query, :count, :home_id)

    # Log full totals for debugging
    Logger.info("#{__MODULE__}: Calculated totals - connected_in_memory=#{totals.total_homes}, connected_in_db=#{total_homes_in_db}, prod=#{Float.round(totals.total_production_kw, 1)}kW, cons=#{Float.round(totals.total_consumption_kw, 1)}kW, battery=#{Float.round(totals.avg_battery_percent, 1)}%")

    # Publish to WAMP for real-time consumers (dashboard)
    # Use database count as authoritative (survives restarts), in-memory as fallback
    totals_with_db_count = Map.merge(totals, %{
      total_homes: max(total_homes_in_db, totals.total_homes),
      connected_homes_count: max(total_homes_in_db, totals.total_homes)
    })
    publish_totals_calculated(state.wamp_client, totals_with_db_count)

    # Store in database for history/charts
    store_totals(totals)

    # Schedule next calculation
    timer = Process.send_after(self(), :calculate_totals, @calc_interval_ms)

    {:noreply, %{state | last_totals: totals, calc_timer: timer}}
  end

  @impl true
  def handle_info(:emit_history, state) do
    # Emit current totals as history event for dashboard charts
    # Dashboard will accumulate these into a rolling history buffer
    if state.last_totals do
      publish_history_updated(state.wamp_client, state.last_totals)
      Logger.debug("#{__MODULE__}: History event emitted")
    else
      Logger.debug("#{__MODULE__}: No totals calculated yet, skipping history emission")
    end

    # Schedule next history emission
    history_timer = Process.send_after(self(), :emit_history, @history_interval_ms)

    {:noreply, %{state | history_timer: history_timer}}
  end

  ## Private Functions

  defp calculate_totals_from_homes(homes) when map_size(homes) == 0 do
    %{
      total_homes: 0,
      total_production_kw: 0.0,
      total_consumption_kw: 0.0,
      avg_battery_percent: 0.0,
      calculated_at: DateTime.utc_now()
    }
  end

  defp calculate_totals_from_homes(homes) do
    {total_production, total_consumption, total_battery} =
      homes
      |> Map.values()
      |> Enum.reduce({0.0, 0.0, 0.0}, fn home, {prod, cons, batt} ->
        {
          prod + home.production_kw,
          cons + home.consumption_kw,
          batt + home.battery_percent
        }
      end)

    home_count = map_size(homes)

    %{
      total_homes: home_count,
      total_production_kw: total_production,
      total_consumption_kw: total_consumption,
      avg_battery_percent: total_battery / home_count,
      calculated_at: DateTime.utc_now()
    }
  end

  defp publish_totals_calculated(wamp_client, totals) do
    case MaculaSdk.Wamp.Client.publish(
      wamp_client,
      "be.cortexiq.projections.totals_calculated",
      [],
      totals
    ) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to publish totals: #{inspect(reason)}")
    end
  end

  defp publish_history_updated(wamp_client, totals) do
    # Publish history event for dashboard charts
    # Convert kW to W for consistency with dashboard expectations
    history_point = %{
      timestamp: DateTime.to_iso8601(totals.calculated_at),
      total_production_w: trunc(totals.total_production_kw * 1000),
      total_consumption_w: trunc(totals.total_consumption_kw * 1000),
      avg_battery_percent: Float.round(totals.avg_battery_percent, 1),
      total_homes: totals.total_homes
    }

    case MaculaSdk.Wamp.Client.publish(
      wamp_client,
      "be.cortexiq.projections.history_updated",
      [],
      history_point
    ) do
      :ok ->
        :ok
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to publish history: #{inspect(reason)}")
    end
  end

  defp store_totals(totals) do
    import Ecto.Query
    alias CortexIqProjections.Repo
    alias CortexIqDashboardSchemas.Projections.SystemStats
    alias CortexIqDashboardSchemas.Projections.HomeState

    # Query total homes from database (all initialized homes)
    total_homes_in_db = Repo.aggregate(HomeState, :count, :home_id)

    # Upsert system_stats (id=1, single row)
    attrs = %{
      id: 1,
      total_homes: total_homes_in_db,  # Total initialized homes from database
      connected_homes_count: totals.total_homes,  # Currently active homes from in-memory aggregation
      total_production_kwh: totals.total_production_kw,
      total_consumption_kwh: totals.total_consumption_kw,
      avg_battery_percent: totals.avg_battery_percent
    }

    Logger.debug("#{__MODULE__}: Writing to DB - #{inspect(attrs)}")

    result = case Repo.get(SystemStats, 1) do
      nil ->
        # Insert new row
        Logger.info("#{__MODULE__}: Inserting new system_stats row")
        %SystemStats{id: 1}
        |> SystemStats.changeset(attrs)
        |> Repo.insert()

      existing ->
        # Update existing row
        Logger.debug("#{__MODULE__}: Updating existing system_stats row")
        existing
        |> SystemStats.changeset(attrs)
        |> Repo.update()
    end

    case result do
      {:ok, _} ->
        Logger.debug("#{__MODULE__}: ✅ Database update successful")
      {:error, changeset} ->
        Logger.error("#{__MODULE__}: ❌ Database update failed - #{inspect(changeset.errors)}")
    end
  rescue
    e ->
      Logger.error("#{__MODULE__}: ❌ Exception storing totals: #{inspect(e)}")
  end
end
