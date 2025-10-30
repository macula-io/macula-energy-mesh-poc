defmodule CortexIqDashboard.EventSubscribers.TimeAdvancedSubscriber do
  @moduledoc """
  Vertical slice subscriber for simulation.time_advanced events.

  Subscribes to: be.cortexiq.simulation.time_advanced
  Broadcasts to: wamp:events (generic channel for simulation time)
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.simulation.time_advanced"
  @pubsub_channel "wamp:events"

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")
    realm_uri = Keyword.get(opts, :realm_uri, "com.test.realm")

    state = %{
      wamp_client: nil,
      bondy_url: bondy_url,
      realm_uri: realm_uri
    }

    # Connect after a short delay
    Process.send_after(self(), :connect, 5_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:connect, state) do
    case MaculaSdk.Wamp.start_link(url: state.bondy_url, realm: state.realm_uri) do
      {:ok, wamp_client} ->
        Logger.info("#{__MODULE__}: Connected to #{state.realm_uri}")
        send(self(), :subscribe)
        {:noreply, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to connect: #{inspect(reason)}")
        Process.send_after(self(), :connect, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:subscribe, %{wamp_client: nil} = state) do
    Process.send_after(self(), :subscribe, 1_000)
    {:noreply, state}
  end

  def handle_info(:subscribe, state) do
    handler = fn topic, event_data ->
      send(self(), {:event, topic, event_data})
    end

    case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, @topic, handler) do
      :ok ->
        Logger.info("#{__MODULE__}: Subscribed to #{@topic}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, topic, event_data}, state) do
    Logger.debug("#{__MODULE__}: Received time advanced event")

    # Broadcast with topic for backward compatibility with LiveViews
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:wamp_event, topic, event_data}
    )

    {:noreply, state}
  end
end
