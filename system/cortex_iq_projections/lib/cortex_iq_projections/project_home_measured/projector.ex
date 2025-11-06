defmodule CortexIqProjections.ProjectHomeMeasured.Projector do
  @moduledoc """
  Broadway pipeline for projecting home_measured events to database with batching.

  ## Performance Characteristics

  - Input rate: ~5000 events/sec (500 homes * 10 Hz)
  - Batch size: 50 events (configurable via BROADWAY_BATCH_SIZE)
  - Batch timeout: 100ms (ensures low latency even at low throughput)
  - Concurrency: 10 processors (configurable via BROADWAY_CONCURRENCY)

  ## Database Writes

  Each home_measured event updates TWO tables:
  1. **home_states** - Latest state (upsert with ON CONFLICT)
  2. **energy_events** - Time-series data (insert with ON CONFLICT DO NOTHING)

  Batching reduces database round-trips from 5000/sec to ~100/sec (50x improvement).

  ## Event Structure (HomeWizard P1 Meter Compatible)

  ```elixir
  %{
    kwargs: %{
      "home_id" => "019a...",
      "timestamp" => "2025-01-15T14:32:00Z",
      "power_w" => -1500.0,  # Negative = exporting to grid
      "energy_import_kwh" => 1250.5,  # Cumulative grid import
      "energy_export_kwh" => 890.3,   # Cumulative grid export
      "state_of_charge_pct" => 75.0,  # Battery %
      "cycles" => 42.0,               # Battery cycles
      "city" => "Amsterdam"
    }
  }
  ```
  """
  use Broadway
  require Logger
  import Ecto.Query
  alias Broadway.Message
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.HomeState
  alias CortexIqDashboardSchemas.TimeSeries.EnergyEvent

  # GenServer Producer for receiving events from Subscriber

  defmodule Producer do
    @moduledoc false
    use GenStage
    alias Broadway.Message

    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    def enqueue_event(event_data) do
      # Broadway registers the producer with its own naming scheme
      # The producer is named: ModuleName.Broadway.Producer_0
      producer_name = :"#{CortexIqProjections.ProjectHomeMeasured.Projector}.Broadway.Producer_0"
      Logger.info("ProjectHomeMeasured.Producer.enqueue_event: Casting to #{inspect(producer_name)}")
      result = GenStage.cast(producer_name, {:enqueue, event_data})
      Logger.info("ProjectHomeMeasured.Producer.enqueue_event: Cast returned #{inspect(result)}")
      result
    end

    @impl true
    def init(_opts) do
      require Logger
      Logger.info("ProjectHomeMeasured.Producer init() called - GenStage producer with handle_demand!")
      {:producer, %{queue: :queue.new(), pending_demand: 0}}
    end

    # GenStage callback - called when Broadway requests messages
    @impl true
    def handle_demand(demand, state) do
      Logger.info("ProjectHomeMeasured.Producer: handle_demand called with incoming_demand=#{demand}, queue_len=#{:queue.len(state.queue)}, pending_demand=#{state.pending_demand}")

      # Add new demand to pending
      total_demand = state.pending_demand + demand

      # Dispatch events from queue
      {messages, queue} = take_from_queue(state.queue, total_demand, [])
      remaining_demand = total_demand - length(messages)

      Logger.info("ProjectHomeMeasured.Producer: Emitting #{length(messages)} messages, remaining_demand=#{remaining_demand}")
      {:noreply, messages, %{state | queue: queue, pending_demand: remaining_demand}}
    end

    # Receive events from subscriber (GenStage callback, NOT GenServer!)
    @impl true
    def handle_cast({:enqueue, event_data}, state) do
      # Add event to queue (DO NOT dispatch immediately - let Broadway pull via handle_demand)
      queue = :queue.in(event_data, state.queue)
      queue_len = :queue.len(queue)

      if rem(queue_len, 100) == 0 do
        Logger.info("ProjectHomeMeasured.Producer: Queue size: #{queue_len}")
      end

      # Return no messages - Broadway will pull via handle_demand when ready
      {:noreply, [], state}
    end

    defp take_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}

    defp take_from_queue(queue, demand, acc) do
      case :queue.out(queue) do
        {{:value, event_data}, queue} ->
          message = %Message{
            data: event_data,
            acknowledger: {__MODULE__, :ack_id, :ack_data}
          }
          take_from_queue(queue, demand - 1, [message | acc])

        {:empty, queue} ->
          {Enum.reverse(acc), queue}
      end
    end
  end

  # Public API

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {Producer, []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: String.to_integer(System.get_env("BROADWAY_CONCURRENCY", "50")),
          max_demand: 10
        ]
      ],
      batchers: [
        database: [
          concurrency: String.to_integer(System.get_env("BROADWAY_BATCH_CONCURRENCY", "20")),
          batch_size: String.to_integer(System.get_env("BROADWAY_BATCH_SIZE", "100")),
          batch_timeout: 100
        ]
      ]
    )
  end

  def enqueue_event(event_data) do
    Producer.enqueue_event(event_data)
  end

  # Broadway Callbacks

  @impl true
  def handle_message(:default, %Message{data: event_data} = message, _context) do
    Logger.info("ProjectHomeMeasured.Projector: handle_message called")
    # Just pass through to batcher - no processing needed here
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_batch(:database, messages, _batch_info, _context) do
    Logger.info("ProjectHomeMeasured.Projector: handle_batch called with #{length(messages)} messages")

    # Extract event data from all messages
    events = Enum.map(messages, & &1.data)

    # Project all events in batch
    project_batch(events)

    # Return messages (Broadway requires this)
    messages
  end

  # Projection Logic (OPTIMIZED: Bulk inserts for 100x performance)

  defp project_batch(events) do
    Logger.info("ProjectHomeMeasured.Projector: project_batch called with #{length(events)} events")

    # Group by home_id and take latest event per home
    events_by_home = Enum.group_by(events, fn event ->
      get_in(event, [:kwargs, "home_id"])
    end)

    latest_events =
      events_by_home
      |> Enum.filter(fn {home_id, _} -> !is_nil(home_id) end)
      |> Enum.map(fn {_home_id, home_events} -> List.last(home_events) end)

    # Build bulk insert data
    {home_states, energy_events} =
      Enum.reduce(latest_events, {[], []}, fn event_data, {states_acc, events_acc} ->
        kwargs = Map.get(event_data, :kwargs, event_data)
        home_id = kwargs["home_id"] || kwargs["unique_id"]

        production_w = kwargs["_production_w"] || 0.0
        consumption_w = kwargs["_consumption_w"] || 0.0
        energy_import_kwh = kwargs["energy_import_kwh"] || 0.0
        energy_export_kwh = kwargs["energy_export_kwh"] || 0.0
        battery_percent = kwargs["state_of_charge_pct"] || 0.0
        simulation_time = parse_datetime(kwargs["timestamp"])
        location = kwargs["city"]
        now = DateTime.utc_now()

        # Home state record for bulk upsert (map format for insert_all)
        home_state = %{
          home_id: home_id,
          location: location,
          production_kw: production_w / 1000.0,
          consumption_kw: consumption_w / 1000.0,
          energy_bought_kwh: energy_import_kwh,
          energy_sold_kwh: energy_export_kwh,
          net_balance_kwh: energy_import_kwh - energy_export_kwh,
          battery_percent: battery_percent,
          last_event_at: simulation_time,
          updated_at: now,
          inserted_at: now
        }

        # Energy event record for bulk insert
        energy_event = %{
          home_id: home_id,
          simulation_time: simulation_time,
          production_watts: production_w,
          consumption_watts: consumption_w,
          battery_percent: battery_percent,
          recorded_at: now
        }

        {[home_state | states_acc], [energy_event | events_acc]}
      end)

    # Bulk upsert home_states (replace all fields except home_id and inserted_at)
    if length(home_states) > 0 do
      {count, _} = Repo.insert_all(
        HomeState,
        home_states,
        on_conflict: {:replace_all_except, [:home_id, :inserted_at]},
        conflict_target: :home_id
      )
      Logger.info("ProjectHomeMeasured.Projector: Bulk upserted #{count} home states")
    end

    # Bulk insert energy_events (ignore duplicates)
    if length(energy_events) > 0 do
      {count, _} = Repo.insert_all(
        EnergyEvent,
        energy_events,
        on_conflict: :nothing,
        conflict_target: [:home_id, :simulation_time]
      )
      Logger.info("ProjectHomeMeasured.Projector: Bulk inserted #{count} energy events")
    end
  rescue
    error ->
      Logger.error("ProjectHomeMeasured.Projector: Error in batch projection: #{inspect(error)}")
      Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
  end

  # Helper Functions

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
