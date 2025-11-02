defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber do
  @moduledoc """
  Subscribes to simulation.time_advanced events.

  Topic: be.cortexiq.simulation.time_advanced
  Notifies: HomeBot via {:simulation_time_tick, simulation_time}
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.simulation.time_advanced"

  ## Client API

  def start_link(opts) do
    home_id = Keyword.fetch!(opts, :home_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(home_id))
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    pool_name = Keyword.get(opts, :pool_name, CortexIqHomes.WampPool)
    home_id = Keyword.fetch!(opts, :home_id)

    state = %{
      pool_name: pool_name,
      home_id: home_id
    }

    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    subscriber_pid = self()

    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    MaculaSdk.Wamp.Pool.subscribe(@topic, handler, %{}, state.pool_name)
    |> log_subscription_result(state.home_id, @topic)

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    kwargs = Map.get(event_data, :kwargs, %{})

    simulation_time =
      kwargs["simulation_time"]
      |> parse_simulation_time()

    state.home_id
    |> CortexIqHomes.HomeBot.whereis()
    |> notify_home_bot({:simulation_time_tick, simulation_time}, state.home_id)

    {:noreply, state}
  end

  ## Private Functions

  defp log_subscription_result(:ok, home_id, topic) do
    Logger.info("#{__MODULE__}: Home #{home_id} subscribed to #{topic}")
  end

  defp log_subscription_result({:error, reason}, home_id, _topic) do
    Logger.error("#{__MODULE__}: Home #{home_id} failed to subscribe: #{inspect(reason)}")
  end

  defp notify_home_bot(nil, _message, home_id) do
    Logger.warning("HomeBot #{home_id} not found")
  end

  defp notify_home_bot(pid, message, _home_id) when is_pid(pid) do
    send(pid, message)
  end

  defp parse_simulation_time(nil), do: nil

  defp parse_simulation_time(iso8601) when is_binary(iso8601) do
    parse_iso8601_result(DateTime.from_iso8601(iso8601))
  end

  defp parse_iso8601_result({:ok, dt, _offset}), do: dt
  defp parse_iso8601_result(_error), do: nil

  defp via_tuple(home_id) do
    {:via, Registry, {CortexIqHomes.Registry, {__MODULE__, home_id}}}
  end
end
