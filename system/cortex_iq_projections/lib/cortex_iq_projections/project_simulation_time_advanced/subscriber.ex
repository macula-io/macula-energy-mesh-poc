defmodule CortexIqProjections.ProjectSimulationTimeAdvanced.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.simulation.time_advanced WAMP events and forwards to projector.

  This subscriber:
  - Connects to WAMP using provided client
  - Subscribes to: "be.cortexiq.simulation.time_advanced"
  - Forwards events to ProjectSimulationTimeAdvanced.Projector (GenServer)
  - Handles low volume (1 event/sec)

  ## Event Flow

  WAMP → handle_event/2 → GenServer.cast/2 → Projector
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

    # Wait for WAMP client to be ready
    Process.send_after(self(), :subscribe, 2000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %{client: client} = state) do
    topic = "be.cortexiq.simulation.time_advanced"

    Logger.info("ProjectSimulationTimeAdvanced.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("ProjectSimulationTimeAdvanced.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("ProjectSimulationTimeAdvanced.Subscriber: ✗ Failed: #{inspect(reason)}")
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("ProjectSimulationTimeAdvanced.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler

  defp handle_event(_topic, event_data) do
    # Forward to GenServer projector
    CortexIqProjections.ProjectSimulationTimeAdvanced.Projector.project_event(event_data)
  end
end
