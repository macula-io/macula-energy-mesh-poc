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
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    state = %{
      wamp_client: wamp_client
    }

    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
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
