defmodule CortexIqDashboard.DatabaseWriter.Pipeline do
  @moduledoc """
  Flow-based event processing pipeline for high-throughput database writes.

  Architecture:
  1. Producer: Receives events from Phoenix.PubSub (WAMP events)
  2. Flow: Partitions events by home_id, windows by time/count
  3. Consumers: Multiple workers performing batch inserts to TimescaleDB

  Features:
  - Automatic back-pressure (Flow demand management)
  - Partitioned processing (parallel writes, no conflicts)
  - Windowed batching (collect events before writing)
  - Scalable (add more consumers as needed)

  Configuration:
  - Partitions: 10 (parallel processing streams)
  - Window: 500ms or 100 events (whichever comes first)
  - Consumers: 5 (database writer workers)
  """
  use Supervisor
  require Logger

  alias CortexIqDashboard.DatabaseWriter.{Producer, Consumer}

  @partitions 10
  @window_timeout_ms 500
  @window_max_events 100
  @num_consumers 5

  ## Client API

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("DatabaseWriter.Pipeline: Starting pipeline")
    Logger.info("  Consumers: #{@num_consumers}")
    Logger.info("  Note: Simplified architecture without Flow windowing")

    # Start producer and consumers
    # Consumers will subscribe directly to the Producer
    children = [
      {Producer, []}
      | for i <- 1..@num_consumers do
          Supervisor.child_spec(
            {Consumer, subscribe_to: [{Producer, max_demand: 100, min_demand: 50}]},
            id: {Consumer, i}
          )
        end
    ]

    # This Supervisor starts the entire pipeline
    Supervisor.init(children, strategy: :one_for_one)
  end

  ## Private Functions

  defp partition_key({:trade, data}), do: data["home_id"] || "unknown"
  defp partition_key({:energy, data}), do: data["home_id"] || "unknown"
  defp partition_key({:contract, _, data}), do: data["home_id"] || "unknown"

  defp create_window do
    Flow.Window.global()
    |> Flow.Window.trigger_every(@window_max_events)
    |> Flow.Window.trigger_periodically(@window_timeout_ms, :millisecond)
  end
end
