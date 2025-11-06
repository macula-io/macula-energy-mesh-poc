defmodule CortexIqHomes.PublishBalanceUpdated.Publisher do
  @moduledoc """
  Publishes balance.updated events to WAMP using the shared pool.
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.balance.updated"

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    pool_name = Keyword.get(opts, :pool_name, CortexIqHomes.WampPool)
    GenServer.start_link(__MODULE__, [home_id: home_id, pool_name: pool_name],
      name: via_tuple(home_id))
  end

  @impl true
  def init(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    pool_name = Keyword.fetch!(opts, :pool_name)
    Logger.debug("PublishBalanceUpdated.Publisher: Started for home #{home_id}")
    {:ok, %{home_id: home_id, pool_name: pool_name}}
  end

  @impl true
  def handle_info({:publish, data}, state) do
    Logger.debug("PublishBalanceUpdated.Publisher: Publishing for home #{state.home_id}")
    case MaculaSdk.Wamp.Pool.publish(@topic, [], data, %{}, state.pool_name) do
      :ok -> Logger.debug("PublishBalanceUpdated.Publisher: ✓ Published")
      {:error, reason} -> Logger.error("PublishBalanceUpdated.Publisher: ✗ Failed: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
