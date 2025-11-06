defmodule CortexIqProjections.CalculateCityTotals.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.home.measured WAMP events and forwards to Aggregator.

  This subscriber:
  - Connects to WAMP using provided client
  - Subscribes to: "be.cortexiq.home.measured"
  - Forwards events to CalculateCityTotals.Aggregator

  ## Event Flow

  WAMP → handle_event/2 → Aggregator.update_home_measurement/1
  """
  use GenServer
  require Logger
  alias MaculaSdk.Wamp.Client

  defmodule State do
    @moduledoc false
    defstruct [:wamp_client, :subscription_status]
  end

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    wamp_client = Keyword.fetch!(opts, :wamp_client)

    state = %State{
      wamp_client: wamp_client,
      subscription_status: :not_subscribed
    }

    # Wait for WAMP client to be ready before subscribing
    Process.send_after(self(), :subscribe, 2000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %{wamp_client: wamp_client} = state) do
    topic = "be.cortexiq.home.measured"

    Logger.info("CalculateCityTotals.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(wamp_client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("CalculateCityTotals.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("CalculateCityTotals.Subscriber: ✗ Failed to subscribe: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("CalculateCityTotals.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler - Forward to Aggregator

  defp handle_event(_topic, event_data) do
    # Forward to Aggregator for city-level aggregation
    CortexIqProjections.CalculateCityTotals.Aggregator.update_home_measurement(event_data)
    :ok
  end
end
