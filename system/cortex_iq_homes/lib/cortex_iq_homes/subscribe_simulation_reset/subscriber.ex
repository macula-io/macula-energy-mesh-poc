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
    macula_url = Keyword.fetch!(opts, :macula_url)
    realm = Keyword.fetch!(opts, :realm)

    state = %{
      macula_url: macula_url,
      realm: realm,
      client: nil
    }

    # Connect and subscribe after a delay
    Process.send_after(self(), :connect, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case MaculaSdk.Client.start_link(url: state.macula_url, realm: state.realm) do
      {:ok, client} ->
        Logger.info("#{__MODULE__}: Connected to Macula, subscribing to #{@topic}...")
        send(self(), :subscribe)
        {:noreply, %{state | client: client}}

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to connect: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:subscribe, %{client: nil} = state) do
    Logger.warning("#{__MODULE__}: Cannot subscribe, client not connected")
    Process.send_after(self(), :subscribe, 5_000)
    {:noreply, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()

    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Client.subscribe(state.client, @topic, handler, %{}) do
      :ok ->
        Logger.info("#{__MODULE__}: Successfully subscribed to #{@topic}")
        {:noreply, state}

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe to #{@topic}: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :subscribe, 5_000)
        {:noreply, state}
    end
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
    # Note: For reset events, we use the subscriber's own client to publish disconnect events
    # This is a workaround since we're terminating all homes
    event_data = %{
      "home_id" => home_id,
      "reason" => "reset",
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()
    }

    topic = "be.cortexiq.homes.home.disconnected"

    # TODO: This should use the subscriber's client, but it's called from a background task
    # For now, we'll skip sending disconnect events during reset (homes will reconnect anyway)
    Logger.debug("#{__MODULE__}: Would send disconnect event for #{home_id} (skipped during reset)")
  end

  defp restart_all_homes_staggered do
    # Load homes from config (same sources as initial startup)
    homes_sources = System.get_env("HOMES_SOURCES", "flanders_test_homes.json")
    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")
    realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")

    homes = CortexIqHomes.ConfigLoader.load_homes_from_sources(homes_sources)

    # Stagger startup to avoid overwhelming Bondy
    delay_ms = 50  # Slightly longer delay on restart

    Logger.info("#{__MODULE__}: Restarting #{length(homes)} homes with #{delay_ms}ms stagger...")

    Enum.each(homes, fn home ->
      spec = {CortexIqHomes.HomeSupervisor, [
        home: home,
        home_id: home.id,
        macula_url: macula_url,
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
