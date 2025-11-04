defmodule CortexIqDashboard.SubscribeHistoryUpdated.Subscriber do
  @moduledoc """
  Vertical slice subscriber for projections.history_updated events.

  Subscribes to: be.cortexiq.projections.history_updated
  Broadcasts to: dashboard:history_updated

  These events are emitted every ~2 seconds with current system totals.
  The LiveView accumulates them into a rolling history buffer for charts.
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.projections.history_updated"
  @pubsub_channel "dashboard:history_updated"

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
    subscriber_pid = self()
    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, @topic, handler) do
      :ok ->
        Logger.info("#{__MODULE__}: Subscribed to #{@topic}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :subscribe, 5_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    Logger.debug("#{__MODULE__}: Received history point - timestamp=#{Map.get(kwargs, "timestamp")}, prod=#{Map.get(kwargs, "total_production_w")}W, cons=#{Map.get(kwargs, "total_consumption_w")}W")

    # Broadcast to internal PubSub for OverviewLive
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:history_updated, kwargs}
    )

    {:noreply, state}
  end
end
