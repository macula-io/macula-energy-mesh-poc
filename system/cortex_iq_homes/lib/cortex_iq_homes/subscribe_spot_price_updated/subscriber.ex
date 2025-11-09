defmodule CortexIqHomes.SubscribeSpotPriceUpdated.Subscriber do
  @moduledoc """
  Subscribes to be.cortexiq.market.spot_price_updated events.

  Topic: be.cortexiq.market.spot_price_updated
  Notifies: HomeBot via {:spot_price_update, data}
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.market.spot_price_updated"

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  @impl true
  def init(opts) do
    client = Keyword.get(opts, :client, CortexIqHomes.WampPool)
    home_id = Keyword.fetch!(opts, :home_id)

    Process.send_after(self(), :subscribe, 2_000)

    {:ok, %{client: client, home_id: home_id}}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()
    handler = fn _topic, event_data -> send(subscriber_pid, {:event, event_data}) end

    MaculaSdk.Client.subscribe(@topic, handler, %{}, state.client)
    |> log_subscription_result(state.home_id, @topic)

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    event_data
    |> Map.get(:kwargs, %{})
    |> Map.get("spot_price")
    |> notify_home_bot_with_data(state.home_id, :spot_price_update)

    {:noreply, state}
  end

  defp log_subscription_result(:ok, home_id, topic) do
    Logger.info("#{__MODULE__}: Home #{home_id} subscribed to #{topic}")
  end

  defp log_subscription_result({:error, reason}, home_id, _topic) do
    Logger.error("#{__MODULE__}: Home #{home_id} failed: #{inspect(reason)}")
  end

  defp notify_home_bot_with_data(data, home_id, message_type) do
    home_id
    |> CortexIqHomes.HomeBot.whereis()
    |> send_to_home_bot({message_type, data}, home_id)
  end

  defp send_to_home_bot(nil, _message, home_id) do
    Logger.warning("HomeBot #{home_id} not found")
  end

  defp send_to_home_bot(pid, message, _home_id) when is_pid(pid) do
    send(pid, message)
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
