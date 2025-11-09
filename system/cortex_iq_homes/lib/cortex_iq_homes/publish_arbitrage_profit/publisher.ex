defmodule CortexIqHomes.PublishArbitrageProfit.Publisher do
  @moduledoc """
  Publishes arbitrage.profit events to WAMP using the shared pool.
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.arbitrage.profit"

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    client = Keyword.get(opts, :client, CortexIqHomes.WampPool)
    GenServer.start_link(__MODULE__, [home_id: home_id, client: client],
      name: via_tuple(home_id))
  end

  @impl true
  def init(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    client = Keyword.fetch!(opts, :client)
    Logger.debug("PublishArbitrageProfit.Publisher: Started for home #{home_id}")
    {:ok, %{home_id: home_id, client: client}}
  end

  @impl true
  def handle_info({:publish, data}, state) do
    Logger.debug("PublishArbitrageProfit.Publisher: Publishing for home #{state.home_id}")
    case MaculaSdk.Client.publish(@topic, [], data, %{}, state.client) do
      :ok -> Logger.debug("PublishArbitrageProfit.Publisher: ✓ Published")
      {:error, reason} -> Logger.error("PublishArbitrageProfit.Publisher: ✗ Failed: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
