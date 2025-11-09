defmodule CortexIqProjections.CalculateMetrics.Aggregator do
  @moduledoc """
  Calculates system performance and health metrics.

  Subscribes to home events, tracks in-memory counters, calculates metrics
  every second, stores in time-series table, and publishes via WAMP.

  ## Architecture

  home.measured → Track event counts → Calculate metrics (every 1000ms)
  → Store in DB (metrics_timeseries) → Publish macula.metrics.totals_calculated

  ## Metrics Calculated

  Performance:
  - events_per_second: Total WAMP events received
  - measurements_per_second: home.measured events
  - meter_readings_per_second: Total meter readings (4 per measurement)

  System Health:
  - homes_online: Currently connected homes
  - homes_total: Total homes seen
  - homes_connected: Active connections

  Energy:
  - total_production_kw: Sum of all home production
  - total_consumption_kw: Sum of all home consumption
  - total_battery_kwh: Sum of all battery current charge
  - total_battery_capacity_kwh: Sum of all battery capacities
  - avg_battery_soc_pct: Average battery state of charge

  Market:
  - active_contracts: Homes with active contracts
  - contract_switches_last_minute: Switches in last 60 seconds
  """
  use GenServer
  require Logger

  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.MetricsTimeseries

  defstruct [
    :client,
    :subscribed,
    # Event counters (reset every second)
    :events_this_second,
    :measurements_this_second,
    :meter_readings_this_second,
    # Event counters for previous second (for publishing)
    :events_last_second,
    :measurements_last_second,
    :meter_readings_last_second,
    # Home tracking
    :homes,  # %{home_id => home_data}
    :contract_switches,  # List of {timestamp_ms, home_id}
    # Timing
    :last_calculation_time,
    :calc_timer,
    :current_simulation_time
  ]

  @calc_interval_ms 1_000  # Calculate metrics every 1 second

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    # Subscribe to home events
    Process.send_after(self(), :subscribe_home_events, 2000)

    # Start periodic metrics calculation
    timer = Process.send_after(self(), :calculate_metrics, @calc_interval_ms)

    Logger.info("CalculateMetrics.Aggregator started - will calculate metrics every #{@calc_interval_ms}ms")

    {:ok, %__MODULE__{
      client: client,
      subscribed: false,
      events_this_second: 0,
      measurements_this_second: 0,
      meter_readings_this_second: 0,
      events_last_second: 0,
      measurements_last_second: 0,
      meter_readings_last_second: 0,
      homes: %{},
      contract_switches: [],
      last_calculation_time: System.monotonic_time(:millisecond),
      calc_timer: timer,
      current_simulation_time: nil
    }}
  end

  @impl true
  def handle_info(:subscribe_home_events, state) do
    Logger.info("#{__MODULE__}: Subscribing to home events (connected, disconnected, measured, time_advanced)")

    subscriber_pid = self()

    # Handler functions
    connected_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_connected_event, event_data})
    end

    disconnected_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_disconnected_event, event_data})
    end

    measured_handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_measured_event, event_data})
    end

    time_advanced_handler = fn _topic, event_data ->
      send(subscriber_pid, {:time_advanced_event, event_data})
    end

    contract_switched_handler = fn _topic, event_data ->
      send(subscriber_pid, {:contract_switched_event, event_data})
    end

    # Attempt all subscriptions
    results = [
      {:connected, MaculaSdk.Client.subscribe(state.client, "be.cortexiq.home.connected", connected_handler)},
      {:disconnected, MaculaSdk.Client.subscribe(state.client, "be.cortexiq.home.disconnected", disconnected_handler)},
      {:measured, MaculaSdk.Client.subscribe(state.client, "be.cortexiq.home.measured", measured_handler)},
      {:time_advanced, MaculaSdk.Client.subscribe(state.client, "be.cortexiq.simulation.time_advanced", time_advanced_handler)},
      {:contract_switched, MaculaSdk.Client.subscribe(state.client, "be.cortexiq.market.contract.switched", contract_switched_handler)}
    ]

    # Check if all succeeded
    all_ok = Enum.all?(results, fn {_event, result} -> result == :ok end)

    case all_ok do
      true ->
        Logger.info("#{__MODULE__}: ✅ Successfully subscribed to all events")
        {:noreply, %{state | subscribed: true}}

      false ->
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
      # Add/update home in tracking map
      home_data = %{
        home_id: home_id,
        connected: true,
        production_kw: 0.0,
        consumption_kw: 0.0,
        battery_kwh: 0.0,
        battery_capacity_kwh: Map.get(kwargs, "battery_capacity_kwh", 10.0),
        battery_soc_pct: 0.0,
        has_contract: false
      }

      new_homes = Map.put(state.homes, home_id, home_data)

      {:noreply, %{state |
        homes: new_homes,
        events_this_second: state.events_this_second + 1
      }}
    else
      {:noreply, %{state | events_this_second: state.events_this_second + 1}}
    end
  end

  @impl true
  def handle_info({:home_disconnected_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")

    new_homes = if home_id do
      case Map.get(state.homes, home_id) do
        nil -> state.homes
        home_data -> Map.put(state.homes, home_id, %{home_data | connected: false})
      end
    else
      state.homes
    end

    {:noreply, %{state |
      homes: new_homes,
      events_this_second: state.events_this_second + 1
    }}
  end

  @impl true
  def handle_info({:home_measured_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")

    # Extract measurement data
    production_w = Map.get(kwargs, "_production_w", 0.0)
    consumption_w = Map.get(kwargs, "_consumption_w", 0.0)
    battery_kwh = Map.get(kwargs, "_battery_kwh", 0.0)
    battery_capacity_kwh = Map.get(kwargs, "_battery_capacity_kwh", 10.0)
    battery_soc_pct = Map.get(kwargs, "state_of_charge_pct", 0.0)

    # Count meter readings (up to 4 meters: elec day/night, gas, water)
    meter_count = count_meters(kwargs)

    new_homes = if home_id do
      case Map.get(state.homes, home_id) do
        nil ->
          # First time seeing this home - initialize
          Map.put(state.homes, home_id, %{
            home_id: home_id,
            connected: true,
            production_kw: production_w / 1000.0,
            consumption_kw: consumption_w / 1000.0,
            battery_kwh: battery_kwh,
            battery_capacity_kwh: battery_capacity_kwh,
            battery_soc_pct: battery_soc_pct,
            has_contract: false
          })

        home_data ->
          # Update existing home
          Map.put(state.homes, home_id, %{home_data |
            production_kw: production_w / 1000.0,
            consumption_kw: consumption_w / 1000.0,
            battery_kwh: battery_kwh,
            battery_soc_pct: battery_soc_pct
          })
      end
    else
      state.homes
    end

    {:noreply, %{state |
      homes: new_homes,
      events_this_second: state.events_this_second + 1,
      measurements_this_second: state.measurements_this_second + 1,
      meter_readings_this_second: state.meter_readings_this_second + meter_count
    }}
  end

  @impl true
  def handle_info({:time_advanced_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    simulation_time = Map.get(kwargs, "simulation_time")

    {:noreply, %{state |
      current_simulation_time: parse_simulation_time(simulation_time),
      events_this_second: state.events_this_second + 1
    }}
  end

  @impl true
  def handle_info({:contract_switched_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")
    now_ms = System.monotonic_time(:millisecond)

    # Add to switches list
    new_switches = [{now_ms, home_id} | state.contract_switches]

    # Update home to mark it has a contract
    new_homes = if home_id do
      case Map.get(state.homes, home_id) do
        nil -> state.homes
        home_data -> Map.put(state.homes, home_id, %{home_data | has_contract: true})
      end
    else
      state.homes
    end

    {:noreply, %{state |
      contract_switches: new_switches,
      homes: new_homes,
      events_this_second: state.events_this_second + 1
    }}
  end

  @impl true
  def handle_info(:calculate_metrics, state) do
    # Capture current counters before resetting
    events_last_second = state.events_this_second
    measurements_last_second = state.measurements_this_second
    meter_readings_last_second = state.meter_readings_this_second

    # Calculate metrics
    metrics = calculate_metrics_snapshot(state, events_last_second, measurements_last_second, meter_readings_last_second)

    # Store in database (async)
    Task.start(fn -> store_metrics(metrics) end)

    # Publish via WAMP (async)
    Task.start(fn -> publish_metrics(state.client, metrics) end)

    # Clean up old contract switches (older than 60 seconds)
    now_ms = System.monotonic_time(:millisecond)
    new_switches = Enum.filter(state.contract_switches, fn {timestamp_ms, _} ->
      now_ms - timestamp_ms < 60_000
    end)

    # Reset counters and schedule next calculation
    timer = Process.send_after(self(), :calculate_metrics, @calc_interval_ms)

    {:noreply, %{state |
      events_this_second: 0,
      measurements_this_second: 0,
      meter_readings_this_second: 0,
      events_last_second: events_last_second,
      measurements_last_second: measurements_last_second,
      meter_readings_last_second: meter_readings_last_second,
      contract_switches: new_switches,
      calc_timer: timer,
      last_calculation_time: now_ms
    }}
  end

  ## Private Functions

  defp count_meters(kwargs) do
    # Count non-nil meters in the event
    meters = [
      Map.get(kwargs, "electricity_day_meter"),
      Map.get(kwargs, "electricity_night_meter"),
      Map.get(kwargs, "gas_meter"),
      Map.get(kwargs, "water_meter")
    ]

    Enum.count(meters, fn meter -> meter != nil end)
  end

  defp calculate_metrics_snapshot(state, events_last_second, measurements_last_second, meter_readings_last_second) do
    homes_list = Map.values(state.homes)
    connected_homes = Enum.filter(homes_list, fn h -> h.connected end)

    # Energy totals
    total_production_kw = Enum.reduce(homes_list, 0.0, fn h, acc -> acc + h.production_kw end)
    total_consumption_kw = Enum.reduce(homes_list, 0.0, fn h, acc -> acc + h.consumption_kw end)
    total_battery_kwh = Enum.reduce(homes_list, 0.0, fn h, acc -> acc + h.battery_kwh end)
    total_battery_capacity_kwh = Enum.reduce(homes_list, 0.0, fn h, acc -> acc + h.battery_capacity_kwh end)

    # Average battery SOC
    avg_battery_soc_pct = if length(homes_list) > 0 do
      Enum.reduce(homes_list, 0.0, fn h, acc -> acc + h.battery_soc_pct end) / length(homes_list)
    else
      0.0
    end

    # Market metrics
    active_contracts = Enum.count(homes_list, fn h -> h.has_contract end)
    contract_switches_last_minute = length(state.contract_switches)

    %{
      timestamp: DateTime.utc_now(),
      simulation_time: state.current_simulation_time,
      # Performance
      events_per_second: events_last_second * 1.0,
      measurements_per_second: measurements_last_second * 1.0,
      meter_readings_per_second: meter_readings_last_second * 1.0,
      # System health
      homes_online: length(connected_homes),
      homes_total: map_size(state.homes),
      homes_connected: length(connected_homes),
      # Energy
      total_production_kw: total_production_kw,
      total_consumption_kw: total_consumption_kw,
      total_battery_kwh: total_battery_kwh,
      total_battery_capacity_kwh: total_battery_capacity_kwh,
      avg_battery_soc_pct: avg_battery_soc_pct,
      # Market
      active_contracts: active_contracts,
      contract_switches_last_minute: contract_switches_last_minute
    }
  end

  defp store_metrics(metrics) do
    changeset = MetricsTimeseries.changeset(%MetricsTimeseries{}, metrics)

    case Repo.insert(changeset) do
      {:ok, _} ->
        Logger.debug("#{__MODULE__}: Stored metrics in database")
      {:error, changeset} ->
        Logger.error("#{__MODULE__}: Failed to store metrics: #{inspect(changeset.errors)}")
    end
  end

  defp publish_metrics(client, metrics) do
    # Convert DateTime to ISO8601 for WAMP
    payload = metrics
      |> Map.put(:timestamp, DateTime.to_iso8601(metrics.timestamp))
      |> Map.put(:simulation_time, if(metrics.simulation_time, do: DateTime.to_iso8601(metrics.simulation_time), else: nil))

    case MaculaSdk.Client.publish(client, "macula.metrics.totals_calculated", [], payload) do
      :ok ->
        Logger.debug("#{__MODULE__}: Published metrics to macula.metrics.totals_calculated")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to publish metrics: #{inspect(reason)}")
    end
  end

  defp parse_simulation_time(nil), do: nil
  defp parse_simulation_time(iso8601) when is_binary(iso8601) do
    case DateTime.from_iso8601(iso8601) do
      {:ok, dt, _offset} -> dt
      _ -> nil
    end
  end
  defp parse_simulation_time(_), do: nil
end
