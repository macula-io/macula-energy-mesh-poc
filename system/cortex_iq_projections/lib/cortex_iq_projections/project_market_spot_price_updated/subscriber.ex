defmodule CortexIqProjections.ProjectMarketSpotPriceUpdated.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.market.spot_price_updated WAMP events and forwards to projector.

  Projects market.spot_price_updated events

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

    Process.send_after(self(), :subscribe, 2000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %{client: client} = state) do
    topic = "be.cortexiq.market.spot_price_updated"

    Logger.info("ProjectMarketSpotPriceUpdated.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("ProjectMarketSpotPriceUpdated.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("ProjectMarketSpotPriceUpdated.Subscriber: ✗ Failed: #{inspect(reason)}")
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("ProjectMarketSpotPriceUpdated.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler

  defp handle_event(_topic, event_data) do
    CortexIqProjections.ProjectMarketSpotPriceUpdated.Projector.project_event(event_data)
  end
end
