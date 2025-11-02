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
    homes: %{},  # %{home_id => %{production_kw, consumption_kw, battery_percent}}
    last_totals: nil,  # Last calculated totals
    calc_timer: nil  # Timer for periodic calculation
  ]

  @calc_interval_ms 500  # Calculate totals every 500ms

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    # Subscribe to home.measured events to track measurements
    Process.send_after(self(), :subscribe_home_measured, 2000)

    # Start periodic totals calculation
    timer = Process.send_after(self(), :calculate_totals, @calc_interval_ms)

    Logger.info("CalculateSystemTotals.Aggregator started")

    {:ok, %__MODULE__{
      wamp_client: wamp_client,
      calc_timer: timer
    }}
  end

  @impl true
  def handle_info(:subscribe_home_measured, state) do
    subscriber_pid = self()
    handler = fn _topic, event_data ->
      send(subscriber_pid, {:home_measured_event, event_data})
    end

    case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, "be.cortexiq.home.measured", handler) do
      :ok ->
        Logger.info("#{__MODULE__}: Subscribed to be.cortexiq.home.measured")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:home_measured_event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})
    home_id = Map.get(kwargs, "home_id")
    production_w = Map.get(kwargs, "_production_w", 0.0)
    consumption_w = Map.get(kwargs, "_consumption_w", 0.0)
    battery_percent = Map.get(kwargs, "state_of_charge_pct", 0.0)

    if home_id do
      # Update in-memory home state
      home_state = %{
        production_kw: production_w / 1000.0,
        consumption_kw: consumption_w / 1000.0,
        battery_percent: battery_percent
      }

      new_homes = Map.put(state.homes, home_id, home_state)
      {:noreply, %{state | homes: new_homes}}
    else
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

    # ALWAYS publish (removed equality check to see if that's the issue)
    Logger.info("#{__MODULE__}: Calculated totals - #{map_size(state.homes)} homes, avg_battery=#{Float.round(totals.avg_battery_percent, 1)}%")

    # Publish to WAMP for real-time consumers (dashboard)
    publish_totals_calculated(state.wamp_client, totals)

    # Store in database for history/charts
    store_totals(totals)

    # Schedule next calculation
    timer = Process.send_after(self(), :calculate_totals, @calc_interval_ms)

    {:noreply, %{state | last_totals: totals, calc_timer: timer}}
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

  defp store_totals(totals) do
    # TODO: Store in system_stats table
    # For now, just log
    Logger.debug("#{__MODULE__}: Would store totals: #{inspect(totals)}")
  end
end
