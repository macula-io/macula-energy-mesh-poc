defmodule CortexIqDashboard.Views.HomesViewAggregator do
  @moduledoc """
  Maintains the Homes view state in-memory.

  Subscribes to home entity state changes and maintains:
  - List of all homes with current state
  - Sorted by various criteria (id, location, production, etc.)
  """
  use GenServer
  require Logger

  defstruct [
    homes: %{},  # %{home_id => home_state}
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
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    new_homes = Map.put(state.homes, home_id, home_state)
    new_state = %{state | homes: new_homes, last_updated_at: DateTime.utc_now()}

    # Schedule throttled broadcast
    {:noreply, schedule_broadcast(new_state)}
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
