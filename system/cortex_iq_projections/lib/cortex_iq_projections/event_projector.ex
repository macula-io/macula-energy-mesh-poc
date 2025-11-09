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
  alias MaculaSdk.Client
  alias CortexIqProjections.WampProducer

  defmodule State do
    @moduledoc false
    defstruct [:client, :connection_status]
  end

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")
    bondy_realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")
    # username = System.get_env("BONDY_USERNAME")
    # password = System.get_env("BONDY_PASSWORD")

    state = %State{
      connection_status: :connecting
    }

    # Start WAMP client connection (anonymous until we fix Bondy auth)
    case Client.start_link(
           url: macula_url,
           realm: bondy_realm,
           # username: username,
           # password: password,
           name: :event_projector_client
         ) do
      {:ok, client} ->
        Logger.info("EventProjector: WAMP client started, connecting to #{macula_url}")

        # Wait for connection before subscribing
        Process.send_after(self(), :subscribe_to_events, 5000)

        {:ok, %{state | client: client}}

      {:error, reason} ->
        Logger.error("EventProjector: Failed to start WAMP client: #{inspect(reason)}")
        # Retry connection
        Process.send_after(self(), :retry_connection, 5000)
        {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_client, _from, state) do
    {:reply, state.client, state}
  end

  @impl true
  def handle_info(:retry_connection, state) do
    {:stop, :retry_connection, state}
  end

  def handle_info(:subscribe_to_events, %{client: client} = state) do
    Logger.info("EventProjector: Subscribing to individual WAMP event topics")

    # Log initial memory
    log_memory_usage("Before WAMP subscription")

    # Individual topic subscriptions (clearer intent, easier debugging)
    topics = [
      # Home lifecycle events
      {"be.cortexiq.home.initialized", &handle_home_event/2},
      {"be.cortexiq.home.connected", &handle_home_event/2},
      {"be.cortexiq.home.disconnected", &handle_home_event/2},
      {"be.cortexiq.home.measured", &handle_home_event/2},
      {"be.cortexiq.home.traded", &handle_home_event/2},

      # Balance tracking
      {"be.cortexiq.balance.updated", &handle_home_event/2},

      # Market events
      {"be.cortexiq.market.contract_proposed", &handle_market_event/2},
      {"be.cortexiq.market.contract_confirmed", &handle_market_event/2},
      {"be.cortexiq.market.contract_rejected", &handle_market_event/2},
      {"be.cortexiq.market.contract_switched", &handle_market_event/2},
      {"be.cortexiq.market.contract_expired", &handle_market_event/2},
      {"be.cortexiq.market.trade_executed", &handle_market_event/2},
      {"be.cortexiq.market.savings_realized", &handle_market_event/2},
      {"be.cortexiq.market.spot_price_updated", &handle_market_event/2},

      # Arbitrage events
      {"be.cortexiq.arbitrage.profit_realized", &handle_market_event/2},

      # Simulation control
      {"be.cortexiq.simulation.time_advanced", &handle_time_advanced/2},
      {"be.cortexiq.simulation.reset", &handle_time_advanced/2}
    ]

    Enum.each(topics, fn {topic, handler} ->
      case Client.subscribe(client, topic, handler, %{}) do
        :ok ->
          Logger.info("EventProjector: ✓ Subscribed to #{topic}")
        {:error, reason} ->
          Logger.error("EventProjector: ✗ Failed to subscribe to #{topic}: #{inspect(reason)}")
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

  # Event Handlers - Forward to Broadway pipeline

  defp handle_home_event(topic, event_data) do
    Logger.info("EventProjector: Received home event: #{topic}")

    # Apply sampling only to high-frequency measurement events
    should_forward = case topic do
      "be.cortexiq.home.measured" -> :rand.uniform(100) <= 10  # Sample 10%
      "be.cortexiq.home.traded" -> :rand.uniform(100) <= 20     # Sample 20%
      _ -> true  # Forward all lifecycle events
    end

    if should_forward do
      Logger.debug("EventProjector: Forwarding event to pipeline: #{topic}")
      WampProducer.enqueue_event({:home_event, topic, event_data})
    end
  end

  defp handle_market_event(topic, event_data) do
    Logger.info("EventProjector: Received market event: #{topic}")
    # Forward all market events (critical for business logic)
    WampProducer.enqueue_event({:market_event, topic, event_data})
  end

  defp handle_time_advanced(topic, event_data) do
    Logger.debug("EventProjector: Received simulation event: #{topic}")
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
