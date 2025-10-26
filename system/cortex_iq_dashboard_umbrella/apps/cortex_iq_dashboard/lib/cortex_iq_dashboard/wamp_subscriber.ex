defmodule CortexIqDashboard.WampSubscriber do
  @moduledoc """
  Subscribes to WAMP topics and broadcasts events via Phoenix.PubSub.

  This allows the Phoenix LiveView dashboard to receive real-time events
  from the WAMP mesh without each LiveView process connecting to WAMP directly.
  """
  use GenServer
  require Logger

  defstruct [:wamp_client, :realm_uri, :subscriptions]

  # Topics to subscribe to
  # NOTE: Bondy prefix matching doesn't work for provider topics, so we subscribe to exact topics
  @simulation_topics [
    "be.cortexiq.simulation.time_advanced",  # Simulation time updates
    "be.cortexiq.simulation.reset"            # Simulation reset events
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Publish a control command to the simulation clock.
  """
  def publish_control_command(command, kwargs \\ %{}) do
    GenServer.call(__MODULE__, {:publish_control, command, kwargs})
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    bondy_url = Keyword.get(opts, :bondy_url, "ws://localhost:18080/ws")
    realm_uri = Keyword.get(opts, :realm_uri, "com.test.realm")

    state = %__MODULE__{
      wamp_client: nil,
      realm_uri: realm_uri,
      subscriptions: %{}
    }

    # Connect asynchronously after Bondy is fully started (5 second delay)
    Process.send_after(self(), {:connect, bondy_url, realm_uri}, 5_000)

    {:ok, state}
  end

  @impl true
  def handle_info({:connect, bondy_url, realm_uri}, state) do
    case MaculaOs.Wamp.start_link(url: bondy_url, realm: realm_uri, name: :wamp_subscriber) do
      {:ok, wamp_client} ->
        Logger.info("WAMP subscriber connected to #{realm_uri}")

        # Wait a bit for connection to establish, then subscribe
        Process.send_after(self(), :subscribe_to_topics, 1_000)

        {:noreply, %{state | wamp_client: wamp_client}}

      {:error, reason} ->
        Logger.error("Failed to connect to WAMP: #{inspect(reason)}")
        # Retry after 5 seconds
        Process.send_after(self(), {:connect, bondy_url, realm_uri}, 5_000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:subscribe_to_topics, %{wamp_client: nil} = state) do
    # Not connected yet, retry
    Process.send_after(self(), :subscribe_to_topics, 1_000)
    {:noreply, state}
  end

  def handle_info(:subscribe_to_topics, state) do
    # Capture subscriber PID for use in handler closures
    subscriber_pid = self()

    # Generic handler for all subscriptions
    handler = fn received_topic, event_data ->
      send(subscriber_pid, {:wamp, {:event, received_topic, event_data}})
    end

    # Subscribe to simulation time (exact topic)
    Enum.each(@simulation_topics, fn topic ->
      case MaculaOs.Wamp.subscribe(state.wamp_client, topic, handler) do
        :ok ->
          Logger.info("Subscribed to WAMP topic: #{topic}")
        {:error, reason} ->
          Logger.error("Failed to subscribe to #{topic}: #{inspect(reason)}")
      end
    end)

    # Subscribe to home measurement topics using prefix matching (HomeWizard-compatible)
    home_prefix = "be.cortexiq.home."
    options = %{match: "prefix"}
    case MaculaOs.Wamp.subscribe(state.wamp_client, home_prefix, handler, options) do
      :ok ->
        Logger.info("Subscribed to WAMP topic: #{home_prefix} (prefix)")
      {:error, reason} ->
        Logger.error("Failed to subscribe to #{home_prefix}: #{inspect(reason)}")
    end

    # Subscribe to market topics using prefix matching
    market_prefix = "be.cortexiq.market."
    case MaculaOs.Wamp.subscribe(state.wamp_client, market_prefix, handler, options) do
      :ok ->
        Logger.info("Subscribed to WAMP topic: #{market_prefix} (prefix)")
      {:error, reason} ->
        Logger.error("Failed to subscribe to #{market_prefix}: #{inspect(reason)}")
    end

    # Subscribe to balance topics using prefix matching
    balance_prefix = "be.cortexiq.balance."
    case MaculaOs.Wamp.subscribe(state.wamp_client, balance_prefix, handler, options) do
      :ok ->
        Logger.info("Subscribed to WAMP topic: #{balance_prefix} (prefix)")
      {:error, reason} ->
        Logger.error("Failed to subscribe to #{balance_prefix}: #{inspect(reason)}")
    end

    # Subscribe to arbitrage topics using prefix matching
    arbitrage_prefix = "be.cortexiq.arbitrage."
    case MaculaOs.Wamp.subscribe(state.wamp_client, arbitrage_prefix, handler, options) do
      :ok ->
        Logger.info("Subscribed to WAMP topic: #{arbitrage_prefix} (prefix)")
      {:error, reason} ->
        Logger.error("Failed to subscribe to #{arbitrage_prefix}: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  # Handle WAMP events received from subscriptions
  @impl true
  def handle_info({:wamp, {:event, topic, event_data}}, state) do
    # Handle simulation reset specially
    if String.ends_with?(topic, ".simulation.reset") do
      Logger.info("WampSubscriber: Received SIMULATION RESET event")

      # Broadcast reset command to all dashboard components
      Phoenix.PubSub.broadcast(
        CortexIqDashboard.PubSub,
        "dashboard:control",
        {:reset_simulation}
      )
    end

    # Route events to database writer based on topic
    forward_to_database_writer(topic, event_data)

    # Log important events at info level, others at debug
    if String.contains?(topic, ".initialized") or String.contains?(topic, ".contract_confirmed") or String.contains?(topic, ".reset") do
      Logger.info("WampSubscriber received event on #{topic}")
    else
      Logger.debug("WampSubscriber received event on #{topic}")
    end

    # Broadcast to Phoenix.PubSub so LiveViews can receive it
    Phoenix.PubSub.broadcast(
      CortexIqDashboard.PubSub,
      "wamp:events",
      {:wamp_event, topic, event_data}
    )

    {:noreply, state}
  end

  def handle_info({:wamp, _other}, state) do
    # Ignore other WAMP messages
    {:noreply, state}
  end

  @impl true
  def handle_call({:publish_control, command, kwargs}, _from, %{wamp_client: nil} = state) do
    Logger.warning("Cannot publish control command '#{command}' - WAMP client not connected")
    {:reply, {:error, :not_connected}, state}
  end

  def handle_call({:publish_control, command, kwargs}, _from, state) do
    topic = "be.cortexiq.simulation.control.#{command}"

    case MaculaOs.Wamp.Client.publish(state.wamp_client, topic, [], kwargs, %{}) do
      :ok ->
        Logger.info("Published control command to #{topic}")
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Failed to publish control command to #{topic}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  ## Private Functions

  defp forward_to_database_writer(topic, event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    cond do
      # Hourly trade events (import/export)
      String.ends_with?(topic, ".home.traded") ->
        Phoenix.PubSub.broadcast(
          CortexIqDashboard.PubSub,
          "dashboard:trade_event",
          {:trade_event, kwargs}
        )

      # HomeWizard-compatible measurement events (production/consumption/battery)
      String.ends_with?(topic, ".home.measured") ->
        Phoenix.PubSub.broadcast(
          CortexIqDashboard.PubSub,
          "dashboard:energy_event",
          {:energy_event, kwargs}
        )

      # Contract confirmed (signed)
      String.ends_with?(topic, ".market.contract_confirmed") ->
        Phoenix.PubSub.broadcast(
          CortexIqDashboard.PubSub,
          "dashboard:contract_event",
          {:contract_event, :signed, kwargs}
        )

      # Contract switched
      String.ends_with?(topic, ".market.contract_switched") ->
        Phoenix.PubSub.broadcast(
          CortexIqDashboard.PubSub,
          "dashboard:contract_event",
          {:contract_event, :switched, kwargs}
        )

      # Contract expired
      String.ends_with?(topic, ".market.contract_expired") ->
        Phoenix.PubSub.broadcast(
          CortexIqDashboard.PubSub,
          "dashboard:contract_event",
          {:contract_event, :expired, kwargs}
        )

      # Ignore other events
      true ->
        :ok
    end
  end
end
