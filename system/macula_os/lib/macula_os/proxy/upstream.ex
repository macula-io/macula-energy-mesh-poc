defmodule MaculaOs.Proxy.Upstream do
  @moduledoc """
  Manages the upstream WAMP connection to Bondy with automatic reconnection.

  This GenServer:
  - Maintains a single connection to Bondy
  - Implements exponential backoff reconnection
  - Queues messages during disconnection
  - Broadcasts connection state changes
  - Routes messages between client handlers and Bondy
  """
  use GenServer
  require Logger

  alias MaculaOs.Wamp.Connection

  defstruct [
    :bondy_url,
    :realm,
    :connection_pid,
    :session_id,
    :status,
    :clients,
    :message_queue,
    :retry_count,
    :retry_timer
  ]

  @max_retry_delay 30_000  # 30 seconds
  @initial_retry_delay 1_000  # 1 second

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get the upstream connection (creates if not exists)"
  def get_connection do
    {:ok, __MODULE__}
  end

  @doc "Get current connection status"
  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    bondy_url = Keyword.get(opts, :bondy_url) || System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = Keyword.get(opts, :realm) || System.get_env("BONDY_REALM") ||
      raise "BONDY_REALM is required (via opts or environment variable)"

    Logger.info("Initializing MaculaOs Upstream to #{bondy_url}")

    state = %__MODULE__{
      bondy_url: bondy_url,
      realm: realm,
      connection_pid: nil,
      session_id: nil,
      status: :disconnected,
      clients: %{},  # client_id => pid
      message_queue: [],
      retry_count: 0,
      retry_timer: nil
    }

    # Start connection attempt
    send(self(), :connect)

    {:ok, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      status: state.status,
      session_id: state.session_id,
      client_count: map_size(state.clients),
      queued_messages: length(state.message_queue)
    }, state}
  end

  @impl true
  def handle_info(:connect, state) do
    Logger.info("Connecting to Bondy at #{state.bondy_url}...")

    case Connection.start_link(url: state.bondy_url, realm: state.realm, handler: self()) do
      {:ok, conn_pid} ->
        Logger.info("Connected to Bondy, waiting for session...")
        {:noreply, %{state | connection_pid: conn_pid, retry_count: 0}}

      {:error, reason} ->
        Logger.error("Failed to connect to Bondy: #{inspect(reason)}")
        schedule_retry(state)
    end
  end

  def handle_info({:wamp, {:connected, session_id}}, state) do
    Logger.info("Upstream session established: #{session_id}")

    # Flush queued messages
    state = flush_message_queue(state)

    # Notify clients
    broadcast_status(:connected, state)

    {:noreply, %{state | session_id: session_id, status: :connected}}
  end

  def handle_info({:wamp, {:disconnected, reason}}, state) do
    Logger.warning("Upstream disconnected: #{inspect(reason)}")

    # Notify clients
    broadcast_status(:disconnected, state)

    # Schedule reconnection
    schedule_retry(%{state |
      connection_pid: nil,
      session_id: nil,
      status: :disconnected
    })
  end

  def handle_info({:wamp, {:subscribed, topic, subscription_id}}, state) do
    # Forward subscription confirmation to relevant client
    # (Need to track which client requested this subscription)
    Logger.debug("Subscribed to #{topic}, sub_id: #{subscription_id}")
    {:noreply, state}
  end

  def handle_info({:wamp, {:published, topic, publication_id}}, state) do
    Logger.debug("Published to #{topic}, pub_id: #{publication_id}")
    {:noreply, state}
  end

  def handle_info({:wamp, {:event, topic, event_data}}, state) do
    # Broadcast event to all connected clients
    # (In production, filter by subscription)
    broadcast_to_clients({:upstream, [:event, topic, event_data]}, state)
    {:noreply, state}
  end

  def handle_info({:wamp, {:error, details}}, state) do
    Logger.error("WAMP error from upstream: #{inspect(details)}")
    # Forward to relevant client if we can determine which one
    {:noreply, state}
  end

  def handle_info({:wamp, _other}, state) do
    # Ignore other WAMP messages for now
    {:noreply, state}
  end

  # Client registration
  def handle_info({:client_connected, client_id, pid}, state) do
    Logger.debug("Client #{client_id} registered")
    Process.monitor(pid)

    clients = Map.put(state.clients, client_id, pid)
    {:noreply, %{state | clients: clients}}
  end

  def handle_info({:client_disconnected, client_id}, state) do
    Logger.debug("Client #{client_id} disconnected")
    clients = Map.delete(state.clients, client_id)
    {:noreply, %{state | clients: clients}}
  end

  # Monitor client processes
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove client by pid
    clients = Enum.reduce(state.clients, %{}, fn {id, client_pid}, acc ->
      if client_pid == pid, do: acc, else: Map.put(acc, id, client_pid)
    end)

    {:noreply, %{state | clients: clients}}
  end

  # Proxy message from client to Bondy
  def handle_info({:proxy_message, client_id, wamp_message}, state) do
    case state.status do
      :connected ->
        # Send to Bondy via Connection
        send(state.connection_pid, {:send_wamp, wamp_message})
        {:noreply, state}

      _ ->
        # Queue message
        Logger.debug("Queueing message from client #{client_id} (upstream disconnected)")
        queue = state.message_queue ++ [{client_id, wamp_message}]
        {:noreply, %{state | message_queue: queue}}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp schedule_retry(state) do
    # Cancel existing timer
    if state.retry_timer do
      Process.cancel_timer(state.retry_timer)
    end

    # Exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (max)
    delay = min(@initial_retry_delay * :math.pow(2, state.retry_count), @max_retry_delay)
    delay = trunc(delay)

    Logger.info("Retrying connection in #{delay}ms (attempt #{state.retry_count + 1})")

    timer = Process.send_after(self(), :connect, delay)

    {:noreply, %{state |
      retry_timer: timer,
      retry_count: state.retry_count + 1
    }}
  end

  defp flush_message_queue(%{message_queue: []} = state), do: state

  defp flush_message_queue(state) do
    Logger.info("Flushing #{length(state.message_queue)} queued messages...")

    Enum.each(state.message_queue, fn {_client_id, wamp_message} ->
      send(state.connection_pid, {:send_wamp, wamp_message})
    end)

    %{state | message_queue: []}
  end

  defp broadcast_status(status, state) do
    message = {:connection_status, status}

    Enum.each(state.clients, fn {_id, pid} ->
      send(pid, message)
    end)
  end

  defp broadcast_to_clients(message, state) do
    Enum.each(state.clients, fn {_id, pid} ->
      send(pid, message)
    end)
  end
end
