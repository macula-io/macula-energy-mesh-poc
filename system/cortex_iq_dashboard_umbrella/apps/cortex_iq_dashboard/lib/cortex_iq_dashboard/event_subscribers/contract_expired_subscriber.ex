defmodule CortexIqDashboard.EventSubscribers.ContractExpiredSubscriber do
  @moduledoc """
  Vertical slice subscriber for market.contract_expired events.

  Subscribes to: be.cortexiq.market.contract_expired
  Broadcasts to: dashboard:contract_event with :expired type
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.market.contract_expired"
  @pubsub_channel "dashboard:contract_event"

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
    handler = fn _topic, event_data ->
      send(self(), {:event, event_data})
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

    Logger.info("#{__MODULE__}: Received contract expired event")

    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:contract_event, :expired, kwargs}
    )

    {:noreply, state}
  end
end
