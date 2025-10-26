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
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "wamp:events")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Logger.info("HomeStateAggregator: Subscribed to WAMP events and dashboard control")
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
  def handle_info({:wamp_event, _subscription_topic, event_data}, state) do
    topic = get_in(event_data, [:details, "topic"]) || "unknown"
    kwargs = event_data[:kwargs] || %{}
    home_id = Map.get(kwargs, "home_id")

    # Only process events that have a home_id in the payload
    if home_id do
      cond do
        String.ends_with?(topic, ".home.initialized") ->
          Logger.info("HomeStateAggregator: Home #{home_id} initialized (#{Map.get(kwargs, "city")})")
          # Initialize event just ensures the aggregate exists - no data to update yet
          ensure_home_aggregate_started(home_id)

        String.ends_with?(topic, ".home.measured") ->
          route_to_home(home_id, :measurement, kwargs)

        String.ends_with?(topic, ".balance.updated") ->
          route_to_home(home_id, :balance, kwargs)

        String.ends_with?(topic, ".market.contract_confirmed") ->
          Logger.info("HomeStateAggregator: Routing contract_confirmed for #{home_id}, provider=#{Map.get(kwargs, "provider_id")}")
          route_to_home(home_id, :contract, kwargs)

        String.ends_with?(topic, ".market.contract_switched") ->
          Logger.info("HomeStateAggregator: Routing contract_switched for #{home_id}")
          route_to_home(home_id, :contract, kwargs)

        true ->
          :ok
      end
    end

    {:noreply, state}
  end

  defp route_to_home(home_id, event_type, kwargs) do
    ensure_home_aggregate_started(home_id)

    case event_type do
      :measurement ->
        # HomeWizard-compatible measurement with all energy data
        internal = Map.get(kwargs, "_internal", %{})
        Logger.info("Routing measurement for #{home_id}: prod_w=#{Map.get(internal, "production_w", "MISSING")} cons_w=#{Map.get(internal, "consumption_w", "MISSING")}")
        HomeAggregate.update_measurement(home_id, kwargs)

      :balance ->
        HomeAggregate.update_balance(home_id, kwargs)

      :contract ->
        HomeAggregate.update_contract(home_id, kwargs)
    end
  end

  defp ensure_home_aggregate_started(home_id) do
    case DynamicSupervisor.start_child(
           CortexIqDashboard.HomeSupervisor,
           {HomeAggregate, home_id}
         ) do
      {:ok, pid} ->
        Logger.info("HomeStateAggregator: Spawned HomeAggregate for #{home_id} (pid: #{inspect(pid)})")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      error ->
        Logger.error("Failed to start HomeAggregate for #{home_id}: #{inspect(error)}")
    end
  end

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
