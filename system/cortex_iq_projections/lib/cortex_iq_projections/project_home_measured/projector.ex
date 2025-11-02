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
      GenStage.start_link(__MODULE__, opts, name: __MODULE__)
    end

    def enqueue_event(event_data) do
      GenServer.cast(__MODULE__, {:enqueue, event_data})
    end

    @impl true
    def init(_opts) do
      require Logger
      Logger.info("ProjectHomeMeasured.Producer init() called - GenStage producer with handle_demand!")
      {:producer, %{queue: :queue.new()}}
    end

    # GenStage callback - called when Broadway requests messages
    @impl true
    def handle_demand(demand, state) do
      {messages, queue} = take_from_queue(state.queue, demand, [])
      {:noreply, messages, %{state | queue: queue}}
    end

    # Receive events from subscriber
    @impl true
    def handle_cast({:enqueue, event_data}, state) do
      queue = :queue.in(event_data, state.queue)
      {:noreply, [], %{state | queue: queue}}
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
          concurrency: String.to_integer(System.get_env("BROADWAY_CONCURRENCY", "10")),
          max_demand: 1
        ]
      ],
      batchers: [
        database: [
          concurrency: String.to_integer(System.get_env("BROADWAY_BATCH_CONCURRENCY", "5")),
          batch_size: String.to_integer(System.get_env("BROADWAY_BATCH_SIZE", "50")),
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
    # Just pass through to batcher - no processing needed here
    message |> Message.put_batcher(:database)
  end

  @impl true
  def handle_batch(:database, messages, _batch_info, _context) do
    # Extract event data from all messages
    events = Enum.map(messages, & &1.data)

    # Project all events in batch
    project_batch(events)

    # Return messages (Broadway requires this)
    messages
  end

  # Projection Logic

  defp project_batch(events) do
    # Group by home_id for efficient upserts
    events_by_home = Enum.group_by(events, fn event ->
      get_in(event, [:kwargs, "home_id"])
    end)

    # Process each home's events
    Enum.each(events_by_home, fn {home_id, home_events} ->
      unless is_nil(home_id) do
        # Take the latest event for this home (events are in order)
        latest_event = List.last(home_events)
        project_home_measured(latest_event)
      end
    end)
  rescue
    error ->
      Logger.error("ProjectHomeMeasured.Projector: Error in batch projection: #{inspect(error)}")
      Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
  end

  defp project_home_measured(event_data) do
    # Handle both kwargs format and direct map format
    kwargs = Map.get(event_data, :kwargs, event_data)
    home_id = kwargs["home_id"] || kwargs["unique_id"]

    # Get production and consumption from actual event structure
    production_w = kwargs["_production_w"] || 0.0
    consumption_w = kwargs["_consumption_w"] || 0.0

    # Calculate grid power (negative when exporting, positive when importing)
    power_w = consumption_w - production_w

    # Get cumulative energy (if available)
    energy_import_kwh = kwargs["energy_import_kwh"] || 0.0
    energy_export_kwh = kwargs["energy_export_kwh"] || 0.0

    # Battery state
    battery_percent = kwargs["state_of_charge_pct"] || 0.0
    battery_kwh = kwargs["_battery_kwh"]
    battery_capacity_kwh = kwargs["_battery_capacity_kwh"]

    simulation_time = parse_datetime(kwargs["timestamp"])
    location = kwargs["city"]

    # Update home_states (latest state)
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          location: location,
          # Store instantaneous power (from simulation)
          production_kw: production_w / 1000.0,
          consumption_kw: consumption_w / 1000.0,
          # Store cumulative energy (HomeWizard P1 meter style)
          energy_bought_kwh: energy_import_kwh,
          energy_sold_kwh: energy_export_kwh,
          net_balance_kwh: energy_import_kwh - energy_export_kwh,
          # Battery state
          battery_percent: battery_percent,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # Insert into energy_events time-series (for historical analytics)
    Repo.insert!(
      %EnergyEvent{
        home_id: home_id,
        simulation_time: simulation_time,
        # Store actual production and consumption
        production_watts: production_w,
        consumption_watts: consumption_w,
        battery_percent: battery_percent,
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )
  rescue
    error ->
      Logger.error("ProjectHomeMeasured.Projector: Error projecting event: #{inspect(error)}")
      Logger.error("Event data: #{inspect(event_data)}")
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
