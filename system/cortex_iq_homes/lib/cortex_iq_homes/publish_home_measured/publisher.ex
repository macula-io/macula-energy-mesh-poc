defmodule CortexIqHomes.PublishHomeMeasured.Publisher do
  @moduledoc """
  Publishes home.measured events to WAMP using the shared pool.
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.home.measured"

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
    Logger.info("PublishHomeMeasured.Publisher: Starting for home #{home_id}")
    {:ok, %{home_id: home_id, pool_name: pool_name}}
  end

  @impl true
  def handle_info({:publish, measurement_data}, state) do
    Logger.debug("PublishHomeMeasured.Publisher: Publishing for home #{state.home_id}")
    case MaculaSdk.Wamp.Pool.publish(@topic, [], measurement_data, %{}, state.pool_name) do
      :ok -> Logger.debug("PublishHomeMeasured.Publisher: ✓ Published for home #{state.home_id}")
      {:error, reason} -> Logger.error("PublishHomeMeasured.Publisher: ✗ Failed: #{inspect(reason)}")
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
