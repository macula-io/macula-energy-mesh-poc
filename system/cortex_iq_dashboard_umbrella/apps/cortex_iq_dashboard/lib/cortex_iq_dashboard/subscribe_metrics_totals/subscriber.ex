defmodule CortexIqDashboard.SubscribeMetricsTotals.Subscriber do
  @moduledoc """
  Vertical slice subscriber for macula.metrics.totals_calculated events.

  Subscribes to: macula.metrics.totals_calculated
  Broadcasts to: dashboard:metrics_totals

  ## Metrics Received

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

  @topic "macula.metrics.totals_calculated"
  @pubsub_channel "dashboard:metrics_totals"

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)

    state = %{
      pool_name: pool_name,
      subscribed: false
    }

    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()
    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Wamp.Pool.subscribe(@topic, handler, %{}, state.pool_name) do
      :ok ->
        Logger.info("#{__MODULE__}: ✅ Subscribed to #{@topic}")
        {:noreply, %{state | subscribed: true}}
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :subscribe, 5_000)
        {:noreply, state}
    end
  rescue
    e ->
      Logger.error("#{__MODULE__}: Exception during subscribe: #{inspect(e)}, retrying in 5s...")
      Process.send_after(self(), :subscribe, 5_000)
      {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    # Log key metrics for visibility
    Logger.info(
      "#{__MODULE__}: Metrics - " <>
      "events/sec=#{Float.round(Map.get(kwargs, "events_per_second", 0.0), 1)}, " <>
      "measurements/sec=#{Float.round(Map.get(kwargs, "measurements_per_second", 0.0), 1)}, " <>
      "meter_readings/sec=#{Float.round(Map.get(kwargs, "meter_readings_per_second", 0.0), 1)}, " <>
      "homes_online=#{Map.get(kwargs, "homes_online", 0)}, " <>
      "homes_total=#{Map.get(kwargs, "homes_total", 0)}"
    )

    # Broadcast to internal PubSub for LiveView
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:metrics_totals, kwargs}
    )

    {:noreply, state}
  end
end
