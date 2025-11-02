defmodule CortexIqUtilities.SubscribeSimulationReset.Subscriber do
  @moduledoc """
  Singleton subscriber for simulation.reset events.

  Topic: be.cortexiq.simulation.reset
  Action: Terminates ALL provider bots and restarts them with staggered initialization

  This is a singleton service (not per-provider) that runs once per application instance.
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
    bondy_url = Keyword.get(opts, :bondy_url)
    realm = Keyword.get(opts, :realm)

    state = %{
      bondy_url: bondy_url,
      realm: realm,
      wamp_client: nil
    }

    # Connect to WAMP and subscribe
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case MaculaSdk.Wamp.Client.start_link(url: state.bondy_url, realm: state.realm) do
      {:ok, wamp_client} ->
        Logger.info("#{__MODULE__}: Connected to WAMP, subscribing to #{@topic}...")
        Process.send_after(self(), :subscribe, 2_000)
        {:noreply, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to connect: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:subscribe, state) do
    if state.wamp_client do
      subscriber_pid = self()

      handler = fn _topic, event_data ->
        send(subscriber_pid, {:event, event_data})
      end

      case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, @topic, handler) do
        :ok ->
          Logger.info("#{__MODULE__}: Successfully subscribed to #{@topic}")
        {:error, reason} ->
          Logger.error("#{__MODULE__}: Failed to subscribe to #{@topic}: #{inspect(reason)}")
          Process.send_after(self(), :subscribe, 5_000)
      end
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    Logger.warning("#{__MODULE__}: Received SIMULATION RESET event!")
    Logger.debug("#{__MODULE__}: Event data: #{inspect(event_data)}")

    # Terminate all provider bots, then restart them with staggered initialization
    terminate_and_restart_all_providers()

    {:noreply, state}
  end

  ## Private Functions

  defp terminate_and_restart_all_providers do
    # Get all provider bots from the dynamic supervisor
    children = DynamicSupervisor.which_children(CortexIqUtilities.BotSupervisor)

    provider_count = length(children)
    Logger.warning("#{__MODULE__}: Terminating #{provider_count} provider bots...")

    # Terminate all provider bots
    Enum.each(children, fn
      {_id, pid, _type, _modules} when is_pid(pid) ->
        DynamicSupervisor.terminate_child(CortexIqUtilities.BotSupervisor, pid)
      _ ->
        :ok
    end)

    Logger.warning("#{__MODULE__}: All provider bots terminated, restarting with staggered initialization...")

    # Restart all providers with staggered delays
    Task.start(fn -> restart_all_providers_staggered() end)

    Logger.info("#{__MODULE__}: Reset complete! #{provider_count} providers will be restarted.")
  end

  defp restart_all_providers_staggered do
    # Load providers from config (same sources as initial startup)
    providers_sources = System.get_env("PROVIDERS_SOURCES", "benelux_energy_providers.json")
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    providers = CortexIqUtilities.ConfigLoader.load_providers_from_sources(providers_sources)

    # Stagger startup to avoid overwhelming Bondy
    delay_ms = 200  # Longer delay for providers (fewer of them)

    Logger.info("#{__MODULE__}: Restarting #{length(providers)} providers with #{delay_ms}ms stagger...")

    Enum.each(providers, fn provider ->
      spec = {CortexIqUtilities.ProviderBot, [
        provider_id: provider.id,
        provider: provider,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqUtilities.BotSupervisor, spec) do
        {:ok, _pid} ->
          Logger.debug("#{__MODULE__}: Restarted provider #{provider.id}")
          :ok

        {:error, reason} ->
          Logger.error("#{__MODULE__}: Failed to restart provider #{provider.id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("#{__MODULE__}: Finished restarting all #{length(providers)} providers!")
  end
end
