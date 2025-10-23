defmodule CortexIqDashboard.WampPublisher do
  @moduledoc """
  Subscribes to Phoenix.PubSub topics and publishes them to WAMP.

  This bridges the gap between internal Phoenix.PubSub messages and external WAMP events.
  """

  use GenServer
  require Logger

  alias MaculaOs.Wamp.Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    realm = Keyword.get(opts, :realm, "energy.hub")
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")

    Logger.info("Starting WAMP Publisher for realm: #{realm}")

    # Subscribe to Phoenix.PubSub topics
    sub_result = Phoenix.PubSub.subscribe(CortexIqDashboard.PubSub, "simulation:time")
    Logger.info("WAMP Publisher: Subscribed to Phoenix.PubSub 'simulation:time' (result: #{inspect(sub_result)})")

    state = %{
      realm: realm,
      bondy_url: bondy_url,
      wamp_client: nil
    }

    # Defer WAMP connection to avoid blocking init
    Process.send_after(self(), :connect_wamp, 100)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect_wamp, state) do
    Logger.info("WAMP Publisher: Connecting to WAMP...")

    case MaculaOs.Wamp.start_link(url: state.bondy_url, realm: state.realm) do
      {:ok, wamp_client} ->
        Logger.info("WAMP Publisher: Connected to WAMP")
        {:noreply, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.warning("WAMP Publisher: Failed to connect: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :connect_wamp, 1000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:simulation_time, event}, state) do
    # Forward simulation time to WAMP
    if state.wamp_client do
      topic = "energy.hub.simulation.time"

      try do
        Client.publish(state.wamp_client, topic, [], event, %{})
        # Log occasionally (every 10 seconds)
        if rem(System.system_time(:second), 10) == 0 do
          Logger.info("Published simulation time to WAMP: #{event["simulation_time"]}")
        end
      rescue
        e ->
          Logger.error("Failed to publish simulation time to WAMP: #{inspect(e)}")
      end
    else
      Logger.warning("WAMP Publisher: No client yet, skipping broadcast")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("WAMP Publisher: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end
end
