defmodule CortexIqDashboard.EventSubscribers.SimulationResetSubscriber do
  @moduledoc """
  Vertical slice subscriber for simulation.reset events.

  Subscribes to: be.cortexiq.simulation.reset
  Broadcasts to: dashboard:control with reset command
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.simulation.reset"
  @pubsub_channel "dashboard:control"

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

    case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, @topic, handler) do
      :ok ->
        Logger.info("#{__MODULE__}: Subscribed to #{@topic}")
      {:error, reason} ->
        Logger.error("#{__MODULE__}: Failed to subscribe: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, _event_data}, state) do
    Logger.info("#{__MODULE__}: Received SIMULATION RESET event")

    # Broadcast reset command to all dashboard components
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      @pubsub_channel,
      {:reset_simulation}
    )

    {:noreply, state}
  end
end
