defmodule CortexIqDashboard.Views.HomesViewAggregator do
  @moduledoc """
  Maintains the Homes view state in-memory.

  Subscribes to home entity state changes and maintains:
  - List of all homes with current state
  - Sorted by various criteria (id, location, production, etc.)

  Scalability: Only tracks homes visible on current page to limit memory usage.
  """
  use GenServer
  require Logger
  alias CortexIqDashboard.Aggregates.HomeAggregate

  defstruct [
    homes: %{},  # %{home_id => home_state}
    tracked_homes: MapSet.new(),  # Set of home_ids currently being tracked (visible on UI)
    last_updated_at: nil,
    broadcast_timer: nil,  # Timer ref for throttling broadcasts
    pending_broadcast: false  # Flag indicating broadcast is scheduled
  ]

  @broadcast_interval_ms 500  # Throttle broadcasts to max 2x per second

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_homes do
    GenServer.call(__MODULE__, :get_homes)
  end

  def get_home(home_id) do
    GenServer.call(__MODULE__, {:get_home, home_id})
  end

  @doc """
  Tell the aggregator which homes to track (visible on current page).
  Aggregates for non-tracked homes will be terminated to save resources.
  """
  def track_homes(home_ids) when is_list(home_ids) do
    GenServer.cast(__MODULE__, {:track_homes, home_ids})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:home")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
    Logger.info("HomesViewAggregator: Started and subscribed to dashboard control")

    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_homes, _from, state) do
    # Return homes as a list, sorted by home_id
    homes_list =
      state.homes
      |> Map.values()
      |> Enum.sort_by(& &1.home_id)

    {:reply, homes_list, state}
  end

  @impl true
  def handle_call({:get_home, home_id}, _from, state) do
    home = Map.get(state.homes, home_id)
    {:reply, home, state}
  end

  @impl true
  def handle_info({:reset_simulation}, _state) do
    Logger.info("HomesViewAggregator: Resetting - clearing all state")

    # Reset to initial state
    new_state = %__MODULE__{}

    # Broadcast empty state to UI (using same message format as normal updates)
    broadcast_view_updated()

    Logger.info("HomesViewAggregator: Reset complete")
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:track_homes, home_ids}, state) do
    new_tracked = MapSet.new(home_ids)
    old_tracked = state.tracked_homes

    # Find homes to stop tracking (destroy their aggregates)
    to_untrack = MapSet.difference(old_tracked, new_tracked)
    # Find homes to start tracking (ensure their aggregates exist)
    to_track = MapSet.difference(new_tracked, old_tracked)

    Logger.info("HomesViewAggregator: Tracking #{MapSet.size(new_tracked)} homes (#{MapSet.size(to_track)} new, #{MapSet.size(to_untrack)} removed)")

    # Terminate aggregates for homes no longer tracked
    Enum.each(to_untrack, fn home_id ->
      case Registry.lookup(CortexIqDashboard.HomeRegistry, home_id) do
        [{pid, _}] ->
          Logger.debug("HomesViewAggregator: Terminating aggregate for #{home_id}")
          DynamicSupervisor.terminate_child(CortexIqDashboard.HomeSupervisor, pid)
        [] ->
          :ok
      end
    end)

    # Ensure aggregates exist for newly tracked homes
    Enum.each(to_track, fn home_id ->
      case DynamicSupervisor.start_child(
             CortexIqDashboard.HomeSupervisor,
             {CortexIqDashboard.Aggregates.HomeAggregate, home_id}
           ) do
        {:ok, _pid} ->
          Logger.debug("HomesViewAggregator: Created aggregate for #{home_id}")
        {:error, {:already_started, _pid}} ->
          # Already exists, that's fine
          :ok
        error ->
          Logger.error("HomesViewAggregator: Failed to create aggregate for #{home_id}: #{inspect(error)}")
      end
    end)

    # Remove untracked homes from state
    new_homes = Map.drop(state.homes, MapSet.to_list(to_untrack))

    new_state = %{state |
      tracked_homes: new_tracked,
      homes: new_homes,
      last_updated_at: DateTime.utc_now()
    }

    # Broadcast updated view
    broadcast_view_updated()

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    # Only store state for tracked homes
    if MapSet.member?(state.tracked_homes, home_id) do
      new_homes = Map.put(state.homes, home_id, home_state)
      new_state = %{state | homes: new_homes, last_updated_at: DateTime.utc_now()}

      # Schedule throttled broadcast
      {:noreply, schedule_broadcast(new_state)}
    else
      # Ignore state changes for non-tracked homes
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:broadcast_now, state) do
    # Timer fired, actually send the broadcast
    broadcast_view_updated()
    {:noreply, %{state | broadcast_timer: nil, pending_broadcast: false}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp broadcast_view_updated do
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "view:homes",
      :view_updated
    )
  end

  defp schedule_broadcast(state) do
    if state.pending_broadcast do
      # Broadcast already scheduled, don't schedule another
      state
    else
      # Schedule a broadcast after interval
      timer_ref = Process.send_after(self(), :broadcast_now, @broadcast_interval_ms)
      %{state | broadcast_timer: timer_ref, pending_broadcast: true}
    end
  end
end
