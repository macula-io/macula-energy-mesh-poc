defmodule CortexIqDashboard.DatabaseWriter.Producer do
  @moduledoc """
  GenStage Producer that subscribes to Phoenix.PubSub events and produces them
  as a stream for the Flow pipeline.

  This producer receives events from the WAMP subscriber and makes them available
  to downstream Flow stages with proper demand-based back-pressure.
  """
  use GenStage
  require Logger

  defstruct [:demand, :queue]

  ## Client API

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("DatabaseWriter.Producer: Starting and subscribing to PubSub events")

    # Subscribe to all event types we want to persist
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:trade_event")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:energy_event")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:contract_event")

    # Initial state: no pending demand, empty queue
    state = %__MODULE__{
      demand: 0,
      queue: :queue.new()
    }

    {:producer, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    # Add incoming demand to current demand
    new_demand = state.demand + incoming_demand

    Logger.debug("DatabaseWriter.Producer: Demand increased by #{incoming_demand}, total: #{new_demand}, queue size: #{:queue.len(state.queue)}")

    # Dispatch as many events as we can satisfy
    {events, new_state} = dispatch_events([], new_demand, state)

    {:noreply, events, new_state}
  end

  @impl true
  def handle_info({:trade_event, event_data}, state) do
    # Trade event from WAMP subscriber
    event = {:trade, event_data}
    Logger.debug("DatabaseWriter.Producer: Received trade event for home #{event_data["home_id"]}")
    handle_event(event, state)
  end

  @impl true
  def handle_info({:energy_event, event_data}, state) do
    # Energy production/consumption event
    event = {:energy, event_data}
    Logger.debug("DatabaseWriter.Producer: Received energy event for home #{event_data["home_id"]}")
    handle_event(event, state)
  end

  @impl true
  def handle_info({:contract_event, event_type, event_data}, state) do
    # Contract signed/switched/expired event
    event = {:contract, event_type, event_data}
    Logger.debug("DatabaseWriter.Producer: Received #{event_type} contract event for home #{event_data["home_id"]}")
    handle_event(event, state)
  end

  ## Private Functions

  defp handle_event(event, state) do
    # Add event to queue
    new_queue = :queue.in(event, state.queue)

    # If we have pending demand, dispatch immediately
    if state.demand > 0 do
      {events, new_state} = dispatch_events([], state.demand, %{state | queue: new_queue})
      {:noreply, events, new_state}
    else
      # No demand, just queue it
      {:noreply, [], %{state | queue: new_queue}}
    end
  end

  defp dispatch_events(events, 0, state) do
    # No more demand, return what we've dispatched
    {Enum.reverse(events), %{state | demand: 0}}
  end

  defp dispatch_events(events, demand, state) do
    case :queue.out(state.queue) do
      {{:value, event}, new_queue} ->
        # We have an event to dispatch
        dispatch_events([event | events], demand - 1, %{state | queue: new_queue})

      {:empty, _queue} ->
        # No more events in queue, save remaining demand
        {Enum.reverse(events), %{state | demand: demand}}
    end
  end
end
