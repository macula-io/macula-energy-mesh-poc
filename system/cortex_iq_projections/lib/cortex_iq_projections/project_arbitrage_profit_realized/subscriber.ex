defmodule CortexIqProjections.ProjectArbitrageProfitRealized.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.arbitrage.profit_realized WAMP events and forwards to projector.

  Projects arbitrage.profit_realized events (battery arbitrage)

  ## Event Flow

  WAMP → handle_event/2 → GenServer.cast/2 → Projector
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

    Process.send_after(self(), :subscribe, 2000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, %{wamp_client: wamp_client} = state) do
    topic = "be.cortexiq.arbitrage.profit_realized"

    Logger.info("ProjectArbitrageProfitRealized.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(wamp_client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("ProjectArbitrageProfitRealized.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("ProjectArbitrageProfitRealized.Subscriber: ✗ Failed: #{inspect(reason)}")
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("ProjectArbitrageProfitRealized.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler

  defp handle_event(_topic, event_data) do
    CortexIqProjections.ProjectArbitrageProfitRealized.Projector.project_event(event_data)
  end
end
