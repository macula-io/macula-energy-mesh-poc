defmodule CortexIqHomes.PublishContractExpired.Publisher do
  @moduledoc """
  Publishes to be.cortexiq.market.contract_expired.

  Receives: {:publish, data} from HomeBot
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.market.contract_expired"

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  def publish(home_id, data) do
    case whereis(home_id) do
      nil -> Logger.warning("Publisher for #{home_id} not found")
      pid -> send(pid, {:publish, data})
    end
  end

  def whereis(home_id) do
    case Registry.lookup(CortexIqHomes.Registry, {__MODULE__, home_id}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @impl true
  def init(opts) do
    pool_name = Keyword.get(opts, :pool_name, CortexIqHomes.WampPool)
    home_id = Keyword.fetch!(opts, :home_id)

    {:ok, %{pool_name: pool_name, home_id: home_id}}
  end

  @impl true
  def handle_info({:publish, data}, state) do
    case MaculaSdk.Wamp.Client.publish(state.wamp_client, @topic, [], data, %{}) do
      :ok -> :ok
      {:error, reason} -> Logger.error("#{__MODULE__}: Failed for #{state.home_id}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
