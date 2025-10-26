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
  alias CortexIqDashboard.DatabaseWriter

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if connected?() do
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")
      Logger.info("SystemStatsAggregator: Subscribed to WAMP events")
    end

    {:ok, %{event_count: 0}}
  end

  @impl true
  def handle_info({:wamp_event, _subscription_topic, event_data}, state) do
    topic = get_in(event_data, [:details, "topic"]) || "unknown"
    kwargs = event_data[:kwargs] || %{}

    cond do
      String.contains?(topic, ".simulation.time") ->
        update_simulation_time(kwargs)

      String.contains?(topic, ".market.contract.switched") ->
        increment_contract_switches()

      true ->
        :ok
    end

    # Recalculate aggregates every 100 events
    new_count = state.event_count + 1

    if rem(new_count, 100) == 0 do
      DatabaseWriter.recalculate_system_aggregates()
    end

    if rem(new_count, 1000) == 0 do
      Logger.info("SystemStatsAggregator: Processed #{new_count} events")
    end

    {:noreply, %{state | event_count: new_count}}
  end

  defp update_simulation_time(kwargs) do
    DatabaseWriter.update_system_stats(%{
      simulation_time: parse_datetime(Map.get(kwargs, "simulation_time")),
      simulation_speed: Map.get(kwargs, "speed"),
      updated_at: DateTime.utc_now()
    })
  end

  defp increment_contract_switches do
    DatabaseWriter.increment_contract_switches()
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(dt) when is_binary(dt), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(_), do: nil

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
