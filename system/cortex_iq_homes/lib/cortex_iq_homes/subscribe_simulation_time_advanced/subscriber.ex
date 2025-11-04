defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber do
  @moduledoc """
  Subscribes to simulation.time_advanced events and broadcasts to all homes via PubSub.

  Subscribes to: be.cortexiq.simulation.time_advanced
  Broadcasts to: homes:simulation_time_tick
  Message format: {:simulation_time_tick, simulation_time}
  """
  use GenServer
  require Logger

  @topic "be.cortexiq.simulation.time_advanced"
  @pubsub_channel "homes:simulation_time_tick"

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("🟢 #{__MODULE__}.init called with opts: #{inspect(opts)}")

    wamp_client = Keyword.fetch!(opts, :wamp_client)

    state = %{
      wamp_client: wamp_client
    }

    Logger.info("✅ #{__MODULE__}: INIT complete - Scheduling subscription in 2 seconds")
    Logger.info("  wamp_client: #{inspect(wamp_client)}")
    Logger.info("  self: #{inspect(self())}")
    Process.send_after(self(), :subscribe, 2_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:subscribe, state) do
    Logger.info("🔔 #{__MODULE__}: Received :subscribe message")
    Logger.info("  wamp_client: #{inspect(state.wamp_client)}")
    Logger.info("  topic: #{@topic}")

    subscriber_pid = self()

    handler = fn _topic, event_data ->
      send(subscriber_pid, {:event, event_data})
    end

    Logger.info("🔌 #{__MODULE__}: Attempting to subscribe to #{@topic}...")

    case MaculaSdk.Wamp.Client.subscribe(state.wamp_client, @topic, handler) do
      :ok ->
        Logger.info("✅ #{__MODULE__}: Successfully subscribed to #{@topic}")
        Logger.info("  Will broadcast to PubSub channel: #{@pubsub_channel}")
      {:error, reason} ->
        Logger.error("❌ #{__MODULE__}: Failed to subscribe: #{inspect(reason)}, retrying in 5s...")
        Process.send_after(self(), :subscribe, 5_000)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:event, event_data}, state) do
    Logger.debug("📥 #{__MODULE__}: Received WAMP event")

    kwargs = Map.get(event_data, :kwargs, %{})

    simulation_time =
      kwargs["simulation_time"]
      |> parse_simulation_time()

    Logger.debug("  simulation_time: #{inspect(simulation_time)}")

    # Broadcast to all homes via PubSub
    result = Phoenix.PubSub.broadcast(
      CortexIqHomes.PubSub,
      @pubsub_channel,
      {:simulation_time_tick, simulation_time}
    )

    Logger.debug("📡 #{__MODULE__}: PubSub.broadcast result: #{inspect(result)}")
    Logger.debug("  channel: #{@pubsub_channel}")
    Logger.debug("  message: {:simulation_time_tick, #{inspect(simulation_time)}}")

    {:noreply, state}
  end

  ## Private Functions

  defp parse_simulation_time(nil), do: nil

  defp parse_simulation_time(iso8601) when is_binary(iso8601) do
    parse_iso8601_result(DateTime.from_iso8601(iso8601))
  end

  defp parse_iso8601_result({:ok, dt, _offset}), do: dt
  defp parse_iso8601_result(_error), do: nil
end
