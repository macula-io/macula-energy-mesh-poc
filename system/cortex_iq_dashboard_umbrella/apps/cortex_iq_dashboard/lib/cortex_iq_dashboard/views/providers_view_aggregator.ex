defmodule CortexIqDashboard.Views.ProvidersViewAggregator do
  @moduledoc """
  Maintains the Providers view state in-memory.

  Subscribes to provider entity state changes and home contract changes
  to calculate:
  - List of all providers with current pricing
  - Market share (number of active contracts)
  - Market share percentage
  """
  use GenServer
  require Logger

  defstruct [
    providers: %{},  # %{provider_id => provider_state}
    home_contracts: %{},  # %{home_id => provider_id}
    last_updated_at: nil,
    broadcast_timer: nil,  # Timer ref for throttling broadcasts
    pending_broadcast: false  # Flag indicating broadcast is scheduled
  ]

  @broadcast_interval_ms 500  # Throttle broadcasts to max 2x per second

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_providers do
    GenServer.call(__MODULE__, :get_providers)
  end

  def get_provider(provider_id) do
    GenServer.call(__MODULE__, {:get_provider, provider_id})
  end

  # GenServer callbacks

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:provider")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "entity:home")
    Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
    Logger.info("ProvidersViewAggregator: Started and subscribed to dashboard control")
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    # Calculate market share and return providers list
    total_contracts = map_size(state.home_contracts)

    providers_list =
      state.providers
      |> Map.values()
      |> Enum.map(fn provider ->
        active_contracts = count_contracts_for_provider(state.home_contracts, provider.provider_id)
        market_share_percent =
          if total_contracts > 0 do
            (active_contracts / total_contracts) * 100.0
          else
            0.0
          end

        %{provider |
          active_contracts: active_contracts,
          market_share_percent: market_share_percent
        }
      end)
      |> Enum.sort_by(& &1.provider_id)

    {:reply, providers_list, state}
  end

  @impl true
  def handle_call({:get_provider, provider_id}, _from, state) do
    provider = Map.get(state.providers, provider_id)
    {:reply, provider, state}
  end

  @impl true
  def handle_info({:reset_simulation}, _state) do
    Logger.info("ProvidersViewAggregator: Resetting - clearing all state")

    # Reset to initial state
    new_state = %__MODULE__{}

    # Broadcast empty state to UI (using same message format as normal updates)
    broadcast_view_updated()

    Logger.info("ProvidersViewAggregator: Reset complete")
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:provider_state_changed, provider_id, provider_state}, state) do
    new_providers = Map.put(state.providers, provider_id, provider_state)
    new_state = %{state | providers: new_providers, last_updated_at: DateTime.utc_now()}

    # Schedule throttled broadcast
    {:noreply, schedule_broadcast(new_state)}
  end

  @impl true
  def handle_info({:home_state_changed, home_id, home_state}, state) do
    # Update home contract mapping when contract changes
    new_home_contracts =
      if home_state.provider_id do
        Map.put(state.home_contracts, home_id, home_state.provider_id)
      else
        Map.delete(state.home_contracts, home_id)
      end

    new_state = %{state | home_contracts: new_home_contracts, last_updated_at: DateTime.utc_now()}

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
      "view:providers",
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

  defp count_contracts_for_provider(home_contracts, provider_id) do
    home_contracts
    |> Map.values()
    |> Enum.count(&(&1 == provider_id))
  end
end
