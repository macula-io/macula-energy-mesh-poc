defmodule CortexIqHomes.PublishHomeInitialized.Publisher do
  @moduledoc """
  Publishes to be.cortexiq.home.initialized.

  Receives: {:publish, data} from HomeBot
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.home.initialized"

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

    Logger.debug("PublishHomeInitialized.Publisher starting for home #{home_id}, pool: #{pool_name}")
    {:ok, %{pool_name: pool_name, home_id: home_id}}
  end

  @impl true
  def handle_info({:publish, data}, state) do
    Logger.info("PublishHomeInitialized: Received {:publish, ...} for home #{state.home_id}")
    Logger.debug("PublishHomeInitialized: Publishing to #{@topic} with data: #{inspect(data)}")
    safe_publish(state.pool_name, data, state.home_id)
    {:noreply, state}
  end

  defp safe_publish(pool_name, data, home_id) do
    try do
      Logger.debug("PublishHomeInitialized: Calling MaculaSdk.Wamp.Pool.publish for #{home_id}...")
      case MaculaSdk.Wamp.Pool.publish(@topic, [], data, %{}, pool_name) do
        :ok ->
          Logger.info("PublishHomeInitialized: ✓ Successfully published to #{@topic} for #{home_id}")
          :ok

        {:error, reason} ->
          Logger.error("PublishHomeInitialized: ❌ Failed for #{home_id}: #{inspect(reason)}")
      end
    catch
      :exit, reason ->
        Logger.error("PublishHomeInitialized: ❌ Pool unavailable for #{home_id}: #{inspect(reason)}")
    end
  end

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
