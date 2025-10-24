defmodule CortexIqDashboard.WampSubscriber do
  @moduledoc """
  Subscribes to WAMP topics and broadcasts events via Phoenix.PubSub.

  This allows the Phoenix LiveView dashboard to receive real-time events
  from the WAMP mesh without each LiveView process connecting to WAMP directly.
  """
  use GenServer
  require Logger

  defstruct [:wamp_client, :realm_uri, :subscriptions]

  # Topics to subscribe to (using prefix matching)
  @topics [
    {"energy.hub.home.", :prefix},      # All home events (production, consumption, storage, contract)
    {"energy.hub.provider.", :prefix},  # All provider events (contract offers, spot prices)
    {"energy.hub.simulation.", :prefix} # Simulation time events
  ]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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

    Enum.each(@topics, fn {topic, match_type} ->
      # Subscribe with match option (prefix matching)
      options = %{match: Atom.to_string(match_type)}

      # Create handler that sends to subscriber_pid (not self() which would be Client)
      handler = fn received_topic, event_data ->
        send(subscriber_pid, {:wamp, {:event, received_topic, event_data}})
      end

      case MaculaOs.Wamp.subscribe(state.wamp_client, topic, handler, options) do
        :ok ->
          Logger.info("Subscribed to WAMP topic: #{topic} (#{match_type})")

        {:error, reason} ->
          Logger.error("Failed to subscribe to #{topic}: #{inspect(reason)}")
      end
    end)

    {:noreply, state}
  end

  # Handle WAMP events received from subscriptions
  @impl true
  def handle_info({:wamp, {:event, topic, event_data}}, state) do
    Logger.debug("WampSubscriber received event on #{topic}")

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

  ## Private Functions
  # (handler now defined inline in handle_info)
end
