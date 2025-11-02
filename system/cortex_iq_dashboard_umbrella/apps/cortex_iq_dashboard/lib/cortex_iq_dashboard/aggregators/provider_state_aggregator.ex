defmodule CortexIqDashboard.Aggregators.ProviderStateAggregator do
  @moduledoc """
  Routes provider events to individual ProviderAggregate GenServers.

  Spawns ProviderAggregate on first event for each provider_id.
  """
  use GenServer
  require Logger
  alias CortexIqDashboard.Aggregates.ProviderAggregate

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    if connected?() do
      # Subscribe to vertical slice channels
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:provider_initialized")
      Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "dashboard:control")
      Logger.info("ProviderStateAggregator: Subscribed to vertical slice channels")
    end

    {:ok, %{}}
  end

  @impl true
  def handle_info({:reset_simulation}, state) do
    Logger.info("ProviderStateAggregator: Resetting - terminating all provider aggregates")

    # Get all children from the DynamicSupervisor
    children = DynamicSupervisor.which_children(CortexIqDashboard.ProviderSupervisor)

    # Terminate each child
    Enum.each(children, fn {_, pid, _, _} ->
      if pid != :undefined do
        DynamicSupervisor.terminate_child(CortexIqDashboard.ProviderSupervisor, pid)
      end
    end)

    Logger.info("ProviderStateAggregator: Reset complete - all provider aggregates terminated")
    {:noreply, state}
  end

  @impl true
  def handle_info({:provider_initialized, kwargs}, state) do
    provider_id = Map.get(kwargs, "provider_id")

    if provider_id do
      Logger.info("ProviderStateAggregator: Provider #{provider_id} initialized")
      ensure_provider_aggregate_started(provider_id)
    end

    {:noreply, state}
  end

  defp route_to_provider(provider_id, kwargs) do
    ensure_provider_aggregate_started(provider_id)
    ProviderAggregate.update_contract_offer(provider_id, kwargs)
  end

  defp ensure_provider_aggregate_started(provider_id) do
    case DynamicSupervisor.start_child(
           CortexIqDashboard.ProviderSupervisor,
           {ProviderAggregate, provider_id}
         ) do
      {:ok, pid} ->
        Logger.info("ProviderStateAggregator: Spawned ProviderAggregate for #{provider_id} (pid: #{inspect(pid)})")
        :ok

      {:error, {:already_started, _pid}} ->
        :ok

      error ->
        Logger.error("Failed to start ProviderAggregate for #{provider_id}: #{inspect(error)}")
    end
  end

  defp connected?, do: Process.whereis(CortexIqDashboard.PubSub) != nil
end
