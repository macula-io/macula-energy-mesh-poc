defmodule CortexIqHomes.SubscribeSimulationReset.Subscriber do
  @moduledoc """
  Singleton subscriber for simulation.reset events.

  Topic: be.cortexiq.simulation.reset
  Action: Broadcasts :publish_initialized to ALL HomeBots to re-initialize after database reset

  This is a singleton service (not per-home) that runs once per application instance.
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.simulation.reset"

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    pool_name = Keyword.get(opts, :pool_name, CortexIqHomes.WampPool)

    state = %{
      pool_name: pool_name
    }

    # Subscribe after a delay to allow WAMP pool to initialize
    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()

    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Wamp.Pool.subscribe(@topic, handler, %{}, state.pool_name) do
      :ok ->
        Logger.info("#{__MODULE__}: Successfully subscribed to #{@topic}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe to #{@topic}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    Logger.warning("#{__MODULE__}: Received SIMULATION RESET event!")
    Logger.debug("#{__MODULE__}: Event data: #{inspect(event_data)}")

    # Terminate all home bots, then restart them with staggered initialization
    terminate_and_restart_all_homes()

    {:noreply, state}
  end

  ## Private Functions

  defp terminate_and_restart_all_homes do
    # Get all home supervisors from the dynamic supervisor
    children = DynamicSupervisor.which_children(CortexIqHomes.BotSupervisor)

    home_count = length(children)
    Logger.warning("#{__MODULE__}: Terminating #{home_count} home bots...")

    # Send disconnect events for all homes BEFORE terminating
    send_disconnect_events_for_all_homes(children)

    # Small delay to ensure disconnect events are published
    Process.sleep(500)

    # Terminate all home supervisors
    Enum.each(children, fn
      {_id, pid, _type, _modules} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(CortexIqHomes.BotSupervisor, pid)
      _ ->
        :ok
    end)

    Logger.warning("#{__MODULE__}: All home bots terminated, restarting with staggered initialization...")

    # Restart all homes with staggered delays
    Task.start(fn -> restart_all_homes_staggered() end)

    Logger.info("#{__MODULE__}: Reset complete! #{home_count} homes will be restarted.")
  end

  defp send_disconnect_events_for_all_homes(children) do
    Logger.info("#{__MODULE__}: Sending disconnect events for #{length(children)} homes...")

    Enum.each(children, fn
      {id, pid, _type, _modules} when is_pid(pid) ->
        # Extract home_id from the supervisor ID
        # The ID format is: {:via, Registry, {CortexIqHomes.Registry, {CortexIqHomes.HomeSupervisor, home_id}}}
        home_id = extract_home_id_from_supervisor_id(id)

        if home_id do
          send_disconnect_event(home_id)
        end

      _ ->
        :ok
    end)

    Logger.info("#{__MODULE__}: Disconnect events sent for all homes")
  end

  defp extract_home_id_from_supervisor_id({:via, Registry, {_registry, {_module, home_id}}}), do: home_id
  defp extract_home_id_from_supervisor_id(_), do: nil

  defp send_disconnect_event(home_id) do
    event_data = %{
      "home_id" => home_id,
      "reason" => "reset",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()
    }

    topic = "be.cortexiq.homes.home.disconnected"

    case MaculaSdk.Wamp.Pool.publish(topic, [event_data], %{}, CortexIqHomes.WampPool) do
      :ok ->
        Logger.debug("#{__MODULE__}: Sent disconnect event for #{home_id}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to send disconnect for #{home_id}: #{inspect(reason)}")
    end
  end

  defp restart_all_homes_staggered do
    # Load homes from config (same sources as initial startup)
    homes_sources = System.get_env("HOMES_SOURCES", "flanders_test_homes.json")
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    homes = CortexIqHomes.ConfigLoader.load_homes_from_sources(homes_sources)

    # Stagger startup to avoid overwhelming Bondy
    delay_ms = 50  # Slightly longer delay on restart

    Logger.info("#{__MODULE__}: Restarting #{length(homes)} homes with #{delay_ms}ms stagger...")

    Enum.each(homes, fn home ->
      spec = {CortexIqHomes.HomeSupervisor, [
        home: home,
        home_id: home.id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          Logger.debug("#{__MODULE__}: Restarted home #{home.id}")
          :ok

        {:error, reason} ->
          Logger.error("#{__MODULE__}: Failed to restart home #{home.id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("#{__MODULE__}: Finished restarting all #{length(homes)} homes!")
  end
end
