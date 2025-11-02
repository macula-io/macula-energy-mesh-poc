defmodule CortexIqDashboard.Aggregators.SystemStatsAggregator do
  @moduledoc """
  Aggregates system-wide statistics from all WAMP events.

  Subscribes to:
  - energy.hub.simulation.time
  - energy.hub.market.contract.switched

  Also periodically recalculates aggregate statistics.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if connected?() do
      # Subscribe to vertical slice channels
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:time_advanced")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:contract_event")
      Logger.info("SystemStatsAggregator: Subscribed to vertical slice channels")
    end

    {:ok, %{event_count: 0}}
  end

  @impl true
  def handle_info({:time_advanced, kwargs}, state) do
    # Dashboard is now in-memory only - no database writes
    _simulation_time = parse_datetime(Map.get(kwargs, "simulation_time"))

    # Track event count for monitoring
    new_count = state.event_count + 1

    if rem(new_count, 1000) == 0 do
      Logger.info("SystemStatsAggregator: Processed #{new_count} events")
    end

    {:noreply, %{state | event_count: new_count}}
  end

  @impl true
  def handle_info({:contract_event, :switched, _kwargs}, state) do
    # Dashboard is now in-memory only - no database writes
    # Track event count for monitoring
    new_count = state.event_count + 1

    if rem(new_count, 1000) == 0 do
      Logger.info("SystemStatsAggregator: Processed #{new_count} events")
    end

    {:noreply, %{state | event_count: new_count}}
  end

  # Ignore other contract event types
  @impl true
  def handle_info({:contract_event, _type, _kwargs}, state) do
    {:noreply, state}
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: nil

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
