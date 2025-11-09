defmodule CortexIqProjections.ProjectHomeMeasured.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.home.measured WAMP events and forwards to Broadway projector.

  This subscriber:
  - Connects to WAMP using provided client
  - Subscribes to: "be.cortexiq.home.measured"
  - Forwards events to ProjectHomeMeasured.Projector (Broadway pipeline)
  - Handles high volume (500 homes * 10 events/sec = 5000 events/sec)

  ## Event Flow

  WAMP → handle_event/2 → Broadway.push_messages/2 → Projector
  """
  use GenServer
  require Logger
  alias MaculaSdk.Client

  defmodule State do
    @moduledoc false
    defstruct [:client, :subscription_status]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    client = Keyword.fetch!(opts, :client)

    state = %State{
      client: client,
      subscription_status: :not_subscribed
    }

    # Wait for WAMP client to be ready before subscribing
    Process.send_after(self(), :subscribe, 2000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %{client: client} = state) do
    topic = "be.cortexiq.home.measured"

    Logger.info("ProjectHomeMeasured.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("ProjectHomeMeasured.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("ProjectHomeMeasured.Subscriber: ✗ Failed to subscribe: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("ProjectHomeMeasured.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler - Forward to Broadway

  defp handle_event(topic, event_data) do
    Logger.info("ProjectHomeMeasured.Subscriber: handle_event called for topic=#{topic}")
    Logger.info("ProjectHomeMeasured.Subscriber: event_data keys: #{inspect(Map.keys(event_data))}")

    # Forward to Broadway pipeline for batching
    # Broadway.push_messages will apply back-pressure if pipeline is overloaded
    result = CortexIqProjections.ProjectHomeMeasured.Projector.enqueue_event(event_data)
    Logger.info("ProjectHomeMeasured.Subscriber: enqueue_event returned: #{inspect(result)}")
    result
  end
end
