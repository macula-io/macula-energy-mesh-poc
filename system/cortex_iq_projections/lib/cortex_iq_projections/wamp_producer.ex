defmodule CortexIqProjections.WampProducer do
  @moduledoc """
  Broadway producer for WAMP events.

  This producer receives WAMP events and forwards them to Broadway
  for processing with proper back-pressure.

  Uses a bounded queue (max 1000 events) to prevent OOM.
  Drops oldest events when queue is full.
  """
  use GenStage
  require Logger

  @max_queue_size 100

  defmodule State do
    @moduledoc false
    defstruct [
      :wamp_client,
      :demand,
      :queue,
      :queue_size,
      :dropped_count
    ]
  end

  # Client API

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Called by WAMP event handlers to enqueue events.
  """
  def enqueue_event(event) do
    GenStage.cast(__MODULE__, {:event, event})
  end

  # GenStage Callbacks

  @impl true
  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    state = %State{
      wamp_client: wamp_client,
      demand: 0,
      queue: :queue.new(),
      queue_size: 0,
      dropped_count: 0
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    # Broadway is requesting more events
    dispatch_events(%{state | demand: state.demand + incoming_demand}, [])
  end

  @impl true
  def handle_cast({:event, event}, state) do
    # New WAMP event received - add to queue if not full
    {new_queue, new_size, new_dropped} =
      if state.queue_size >= @max_queue_size do
        # Queue full - drop oldest event
        {_dropped, queue_after_drop} = :queue.out(state.queue)
        queue_with_new = :queue.in(event, queue_after_drop)

        # Log dropped events periodically (every 100)
        dropped = state.dropped_count + 1
        if rem(dropped, 100) == 0 do
          Logger.warning("WampProducer: Dropped #{dropped} events due to queue overflow (max: #{@max_queue_size})")
        end

        {queue_with_new, state.queue_size, dropped}
      else
        # Queue has space - add event
        {:queue.in(event, state.queue), state.queue_size + 1, state.dropped_count}
      end

    dispatch_events(%{state | queue: new_queue, queue_size: new_size, dropped_count: new_dropped}, [])
  end

  # Private Functions

  defp dispatch_events(%{demand: 0} = state, events) do
    {:noreply, Enum.reverse(events), state}
  end

  defp dispatch_events(%{queue: queue, demand: demand, queue_size: size} = state, events) do
    case :queue.out(queue) do
      {{:value, event}, new_queue} ->
        # Wrap event in Broadway message format
        broadway_message = %Broadway.Message{
          data: event,
          acknowledger: {__MODULE__, :ack_id, :ok}
        }

        dispatch_events(
          %{state | queue: new_queue, demand: demand - 1, queue_size: size - 1},
          [broadway_message | events]
        )

      {:empty, _queue} ->
        {:noreply, Enum.reverse(events), state}
    end
  end

  # Acknowledger callbacks (Broadway requires these, but we don't need to ack WAMP events)
  def ack(:ack_id, _successful, _failed) do
    :ok
  end
end
