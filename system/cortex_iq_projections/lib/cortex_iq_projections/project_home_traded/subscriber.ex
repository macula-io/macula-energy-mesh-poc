defmodule CortexIqProjections.ProjectHomeTraded.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.home.traded WAMP events and forwards to projector.

  Projects home.traded events (energy buy/sell transactions)

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
    topic = "be.cortexiq.home.traded"

    Logger.info("ProjectHomeTraded.Subscriber: Subscribing to #{topic}")

    case Client.subscribe(client, topic, &handle_event/2, %{}) do
      :ok ->
        Logger.info("ProjectHomeTraded.Subscriber: ✓ Subscribed to #{topic}")
        {:noreply, %{state | subscription_status: :subscribed}}

      {:error, reason} ->
        Logger.error("ProjectHomeTraded.Subscriber: ✗ Failed: #{inspect(reason)}")
        Process.send_after(self(), :subscribe, 5000)
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("ProjectHomeTraded.Subscriber: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handler

  defp handle_event(_topic, event_data) do
    CortexIqProjections.ProjectHomeTraded.Projector.project_event(event_data)
  end
end
