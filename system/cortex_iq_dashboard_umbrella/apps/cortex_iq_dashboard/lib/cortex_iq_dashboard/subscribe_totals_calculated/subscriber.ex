defmodule CortexIqDashboard.SubscribeTotalsCalculated.Subscriber do
  @moduledoc """
  Vertical slice subscriber for projections.totals_calculated events.

  Subscribes to: be.cortexiq.projections.totals_calculated
  Broadcasts to: dashboard:totals_calculated
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.projections.totals_calculated"
  @pubsub_channel "dashboard:totals_calculated"

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
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    Logger.info("#{__MODULE__}: Received totals - homes=#{Map.get(kwargs, "total_homes")}, avg_battery=#{Float.round(Map.get(kwargs, "avg_battery_percent", 0.0), 1)}%")

    # Broadcast to internal PubSub for OverviewLive
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:totals_calculated, kwargs}
    )

    {:noreply, state}
  end
end
