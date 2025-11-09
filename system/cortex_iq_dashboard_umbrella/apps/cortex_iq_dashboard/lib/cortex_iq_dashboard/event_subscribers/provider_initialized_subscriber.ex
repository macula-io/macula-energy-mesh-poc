defmodule CortexIqDashboard.EventSubscribers.ProviderInitializedSubscriber do
  @moduledoc """
  Vertical slice subscriber for provider.initialized events.

  Subscribes to: be.cortexiq.provider.initialized
  Broadcasts to: dashboard:provider_initialized
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.provider.initialized"
  @pubsub_channel "dashboard:provider_initialized"

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
    subscriber_pid = self()  # Capture subscriber PID before creating closure
    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Client.subscribe(state.wamp_client, @topic, handler) do
      :ok ->
        Logger.info("#{__MODULE__}: Subscribed to #{@topic}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    Logger.info("#{__MODULE__}: Received provider initialized event")

    # Broadcast to vertical slice channel
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:provider_initialized, kwargs}
    )

    {:noreply, state}
  end
end
