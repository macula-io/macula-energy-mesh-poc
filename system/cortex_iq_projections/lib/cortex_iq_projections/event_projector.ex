defmodule CortexIqProjections.EventProjector do
  @moduledoc """
  Subscribes to WAMP events and forwards them to Broadway pipeline.

  This module acts as a bridge between WAMP and Broadway:
  - Subscribes to WAMP topics
  - Forwards events to WampProducer for processing by EventPipeline
  - Broadway provides back-pressure and batching for high throughput
  """
  use GenServer
  require Logger
  alias MaculaSdk.Wamp.Client
  alias CortexIqProjections.WampProducer

  defmodule State do
    @moduledoc false
    defstruct [:wamp_client, :connection_status]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    bondy_realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    # TODO: Re-enable authentication once we fix the wamp.error.not_auth_method issue
    # username = System.get_env("BONDY_USERNAME")
    # password = System.get_env("BONDY_PASSWORD")

    state = %State{
      connection_status: :connecting
    }

    # Start WAMP client connection (anonymous for now)
    case Client.start_link(
           url: bondy_url,
           realm: bondy_realm,
           name: :event_projector_wamp_client
         ) do
      {:ok, wamp_client} ->
        Logger.info("EventProjector: WAMP client started, connecting to #{bondy_url}")

        # Wait for connection before subscribing
        Process.send_after(self(), :subscribe_to_events, 5000)

        {:ok, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.error("EventProjector: Failed to start WAMP client: #{inspect(reason)}")
        # Retry connection
        Process.send_after(self(), :retry_connection, 5000)
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_wamp_client, _from, state) do
    {:reply, state.wamp_client, state}
  end

  @impl true
  def handle_info(:retry_connection, state) do
    {:stop, :retry_connection, state}
  end

  def handle_info(:subscribe_to_events, %{wamp_client: wamp_client} = state) do
    Logger.info("EventProjector: Subscribing to WAMP event topics")

    # Log initial memory
    log_memory_usage("Before WAMP subscription")

    topics = [
      # Home events - wildcard prefix match (matches be.cortexiq.home.*)
      {"be.cortexiq.home.", &handle_home_event/2, %{match: "prefix"}},

      # Provider events - wildcard prefix match (matches be.cortexiq.provider.*)
      {"be.cortexiq.provider.", &handle_provider_event/2, %{match: "prefix"}},

      # Market events - wildcard prefix match (matches be.cortexiq.market.*)
      {"be.cortexiq.market.", &handle_market_event/2, %{match: "prefix"}},

      # Simulation time - exact match
      {"be.cortexiq.simulation.time_advanced", &handle_time_advanced/2, %{}}
    ]

    Enum.each(topics, fn {topic, handler, options} ->
      case Client.subscribe(wamp_client, topic, handler, options) do
        :ok ->
          Logger.info("EventProjector: Subscribed to #{topic}")
        {:error, reason} ->
          Logger.error("EventProjector: Failed to subscribe to #{topic}: #{inspect(reason)}")
      end
    end)

    log_memory_usage("After WAMP subscription")

    # Schedule periodic memory logging every 10 seconds
    Process.send_after(self(), :log_memory, 10_000)

    {:noreply, %{state | connection_status: :connected}}
  end

  def handle_info(:log_memory, state) do
    log_memory_usage("Periodic check")
    Process.send_after(self(), :log_memory, 10_000)
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("EventProjector: Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Event Handlers - Forward to Broadway with 10% sampling

  defp handle_home_event(topic, event_data) do
    # Sample 10% of home events to reduce load
    if :rand.uniform(100) <= 10 do
      WampProducer.enqueue_event({:home_event, topic, event_data})
    end
  end

  defp handle_provider_event(topic, event_data) do
    # Forward all provider events (low volume)
    WampProducer.enqueue_event({:provider_event, topic, event_data})
  end

  defp handle_market_event(topic, event_data) do
    # Forward all market events (important for contracts)
    WampProducer.enqueue_event({:market_event, topic, event_data})
  end

  defp handle_time_advanced(topic, event_data) do
    # Forward all time events (critical for simulation state)
    WampProducer.enqueue_event({:time_advanced, topic, event_data})
  end

  # Memory Monitoring

  defp log_memory_usage(context) do
    memory = :erlang.memory()
    total_mb = memory[:total] / 1_048_576
    processes_mb = memory[:processes] / 1_048_576
    system_mb = memory[:system] / 1_048_576
    atom_mb = memory[:atom] / 1_048_576
    binary_mb = memory[:binary] / 1_048_576
    ets_mb = memory[:ets] / 1_048_576

    Logger.info("""
    EventProjector Memory (#{context}):
      Total: #{Float.round(total_mb, 2)} MB
      Processes: #{Float.round(processes_mb, 2)} MB
      System: #{Float.round(system_mb, 2)} MB
      Atoms: #{Float.round(atom_mb, 2)} MB
      Binaries: #{Float.round(binary_mb, 2)} MB
      ETS: #{Float.round(ets_mb, 2)} MB
      Process count: #{:erlang.system_info(:process_count)}
    """)
  end

end
