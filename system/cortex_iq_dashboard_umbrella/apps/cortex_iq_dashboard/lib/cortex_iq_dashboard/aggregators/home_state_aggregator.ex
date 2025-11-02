defmodule CortexIqDashboard.Aggregators.HomeStateAggregator do
  @moduledoc """
  Routes home events to individual HomeAggregate GenServers.

  Spawns HomeAggregate on first event for each home_id.
  """
  use GenServer
  require Logger
  alias CortexIqDashboard.Aggregates.HomeAggregate

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if connected?() do
      # Subscribe to vertical slice channels
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:home_initialized")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:energy_event")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:contract_event")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Logger.info("HomeStateAggregator: Subscribed to vertical slice channels")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:reset_simulation}, state) do
    Logger.info("HomeStateAggregator: Resetting - terminating all home aggregates")

    # Get all children from the DynamicSupervisor
    children = DynamicSupervisor.which_children(CortexIqDashboard.HomeSupervisor)

    # Terminate each child
    Enum.each(children, fn {_, pid, _, _} ->
      if pid != :undefined do
        DynamicSupervisor.terminate_child(CortexIqDashboard.HomeSupervisor, pid)
      end
    end)

    Logger.info("HomeStateAggregator: Reset complete - all home aggregates terminated")
    {:noreply, state}
  end

  @impl true
  def handle_info({:home_initialized, kwargs}, state) do
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      Logger.info("HomeStateAggregator: Home #{home_id} initialized (#{Map.get(kwargs, "city")})")
      # With pagination, HomesViewAggregator manages aggregate lifecycle
      # We don't create aggregates here - only for tracked (visible) homes
      # The aggregate will be created when the home becomes visible on a page
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:energy_event, kwargs}, state) do
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      route_to_home(home_id, :measurement, kwargs)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:contract_event, :signed, kwargs}, state) do
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      Logger.info("HomeStateAggregator: Routing contract_confirmed for #{home_id}, provider=#{Map.get(kwargs, "provider_id")}")
      route_to_home(home_id, :contract, kwargs)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:contract_event, :switched, kwargs}, state) do
    home_id = Map.get(kwargs, "home_id")

    if home_id do
      Logger.info("HomeStateAggregator: Routing contract_switched for #{home_id}")
      route_to_home(home_id, :contract, kwargs)
    end

    {:noreply, state}
  end

  defp route_to_home(home_id, event_type, kwargs) do
    # Only route to aggregates that exist (i.e., homes that are tracked/visible)
    # HomesViewAggregator manages aggregate lifecycle based on page visibility
    if home_aggregate_exists?(home_id) do
      case event_type do
        :measurement ->
          # HomeWizard P1 Meter compatible measurement (DSMR 5.0)
          production_w = Map.get(kwargs, "_production_w", 0)
          consumption_w = Map.get(kwargs, "_consumption_w", 0)
          power_w = Map.get(kwargs, "power_w", 0)
          energy_import = Map.get(kwargs, "energy_import_kwh", 0)
          energy_export = Map.get(kwargs, "energy_export_kwh", 0)
          battery_soc = Map.get(kwargs, "state_of_charge_pct", 0)
          Logger.debug("Routing HomeWizard measurement for #{home_id}: production=#{production_w}W, consumption=#{consumption_w}W, grid=#{power_w}W, import=#{energy_import}kWh, export=#{energy_export}kWh, battery=#{battery_soc}%")
          HomeAggregate.update_measurement(home_id, kwargs)

        :balance ->
          HomeAggregate.update_balance(home_id, kwargs)

        :contract ->
          HomeAggregate.update_contract(home_id, kwargs)
      end
    else
      # Home not tracked (not visible on current page) - skip event
      # This is normal and expected with pagination
      :skip
    end
  end

  # Check if a HomeAggregate exists for this home_id
  # If it exists, the home is being tracked (visible on current page)
  defp home_aggregate_exists?(home_id) do
    case Registry.lookup(CortexIqDashboard.HomeRegistry, home_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
