defmodule CortexIqDashboard.EventSubscribers.CityMeasuredSubscriber do
  @moduledoc """
  Vertical slice subscriber for city.measured events.

  Subscribes to: be.cortexiq.city.measured
  Broadcasts to: dashboard:city_measured
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.city.measured"
  @pubsub_channel "dashboard:city_measured"

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

    # Subscribe immediately after short delay to allow WAMP client to connect
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
    # City totals payload is in args (first element), not kwargs
    args = Map.get(event_data, :args, [])
    city_data = List.first(args) || %{}

    Logger.info("#{__MODULE__}: Received city measured event for #{Map.get(city_data, "city_name")}")

    # Broadcast to vertical slice channel
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:city_measured, city_data}
    )

    {:noreply, state}
  end
end
