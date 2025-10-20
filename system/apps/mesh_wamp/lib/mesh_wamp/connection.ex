defmodule MeshWamp.Connection do
  @moduledoc """
  WebSocket connection to WAMP router (Bondy).

  Manages the WebSocket connection and WAMP session lifecycle.
  """
  use WebSockex
  require Logger
  alias MeshWamp.Protocol

  @default_url "ws://localhost:18082/ws"
  @default_realm "com.example.realm"

  defmodule State do
    @moduledoc false
    defstruct [
      :url,
      :realm,
      :session_id,
      :status,
      :pending_requests,
      :subscriptions,
      :client_pid
    ]
  end

  # Client API

  @doc """
  Start a WAMP connection.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (default: com.example.realm)
  - `:client_pid` - PID to send messages to (optional)
  """
  def start_link(opts \\ []) do
    url = Keyword.get(opts, :url, @default_url)
    realm = Keyword.get(opts, :realm, @default_realm)
    client_pid = Keyword.get(opts, :client_pid)

    state = %State{
      url: url,
      realm: realm,
      status: :connecting,
      pending_requests: %{},
      subscriptions: %{},
      client_pid: client_pid
    }

    # Add WAMP WebSocket subprotocol header
    websocket_opts = Keyword.merge(opts, [
      extra_headers: [{"Sec-WebSocket-Protocol", "wamp.2.json"}]
    ])

    WebSockex.start_link(url, __MODULE__, state, websocket_opts)
  end

  @doc """
  Publish a message to a topic.
  """
  def publish(pid, topic, args \\ [], kwargs \\ %{}, options \\ %{}) do
    WebSockex.cast(pid, {:publish, topic, args, kwargs, options})
  end

  @doc """
  Subscribe to a topic.
  """
  def subscribe(pid, topic, options \\ %{}) do
    WebSockex.cast(pid, {:subscribe, topic, options})
  end

  @doc """
  Disconnect from WAMP router.
  """
  def disconnect(pid) do
    WebSockex.cast(pid, :disconnect)
  end

  # WebSockex Callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("WebSocket connected to #{state.url}")

    # Send HELLO message to ourselves asynchronously
    send(self(), :send_hello)

    {:ok, state}
  end

  @impl true
  def handle_info(:send_hello, state) do
    # Send HELLO message with anonymous authentication
    # Following bondy-demo-marketplace pattern
    hello = Protocol.hello_message(state.realm, %{
      "authid" => "anonymous",
      "authmethods" => ["anonymous"],
      "roles" => %{
        "publisher" => %{},
        "subscriber" => %{}
      }
    })

    encoded = Protocol.encode(hello)
    Logger.info("Sending HELLO: #{encoded}")
    frame = {:text, encoded}
    {:reply, frame, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Received unexpected info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    Logger.debug("Received WAMP message: #{msg}")

    case Protocol.decode(msg) do
      {:ok, message} ->
        Logger.debug("Decoded message: #{inspect(message)}")
        handle_wamp_message(message, state)

      {:error, reason} ->
        Logger.error("Failed to decode WAMP message: #{inspect(reason)}")
        {:ok, state}
    end
  end

  def handle_frame(frame, state) do
    Logger.debug("Received frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl true
  def handle_cast({:publish, topic, args, kwargs, options}, state) do
    case state.status do
      :connected ->
        request_id = generate_request_id()
        message = Protocol.publish_message(request_id, topic, args, kwargs, options)
        frame = {:text, Protocol.encode(message)}

        new_state = put_in(state.pending_requests[request_id], {:publish, topic})
        {:reply, frame, new_state}

      _ ->
        Logger.warning("Cannot publish: not connected")
        {:ok, state}
    end
  end

  def handle_cast({:subscribe, topic, options}, state) do
    case state.status do
      :connected ->
        request_id = generate_request_id()
        message = Protocol.subscribe_message(request_id, topic, options)
        frame = {:text, Protocol.encode(message)}

        new_state = put_in(state.pending_requests[request_id], {:subscribe, topic})
        {:reply, frame, new_state}

      _ ->
        Logger.warning("Cannot subscribe: not connected")
        {:ok, state}
    end
  end

  def handle_cast(:disconnect, state) do
    message = Protocol.goodbye_message()
    frame = {:text, Protocol.encode(message)}
    {:close, frame, state}
  end

  @impl true
  def handle_disconnect(%{reason: reason}, state) do
    Logger.info("WebSocket disconnected: #{inspect(reason)}")
    {:ok, %{state | status: :disconnected, session_id: nil}}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("Connection terminating: #{inspect(reason)}")
    :ok
  end

  # Private Functions

  defp handle_wamp_message(message, state) do
    case Protocol.parse_message(message) do
      {:welcome, %{session_id: session_id, details: details}} ->
        Logger.info("WAMP session established: #{session_id}")
        Logger.debug("Session details: #{inspect(details)}")

        new_state = %{state | status: :connected, session_id: session_id}
        notify_client(state, {:connected, session_id})
        {:ok, new_state}

      {:abort, %{reason: reason}} ->
        Logger.error("WAMP connection aborted: #{reason}")
        {:close, state}

      {:goodbye, %{reason: reason}} ->
        Logger.info("WAMP goodbye: #{reason}")
        {:close, state}

      {:published, %{request_id: request_id, publication_id: pub_id}} ->
        handle_published(request_id, pub_id, state)

      {:subscribed, %{request_id: request_id, subscription_id: sub_id}} ->
        handle_subscribed(request_id, sub_id, state)

      {:event, event_data} ->
        handle_event(event_data, state)

      {:error, error_data} ->
        Logger.error("WAMP error: #{inspect(error_data)}")
        {:ok, state}

      {:unknown, msg} ->
        Logger.warning("Unknown WAMP message: #{inspect(msg)}")
        {:ok, state}
    end
  end

  defp handle_published(request_id, publication_id, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{:publish, topic}, pending_requests} ->
        Logger.debug("Published to #{topic}, publication_id: #{publication_id}")
        notify_client(state, {:published, topic, publication_id})
        {:ok, %{state | pending_requests: pending_requests}}

      {nil, _} ->
        Logger.warning("Received PUBLISHED for unknown request: #{request_id}")
        {:ok, state}
    end
  end

  defp handle_subscribed(request_id, subscription_id, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{:subscribe, topic}, pending_requests} ->
        Logger.info("Subscribed to #{topic}, subscription_id: #{subscription_id}")

        subscriptions = Map.put(state.subscriptions, subscription_id, topic)
        notify_client(state, {:subscribed, topic, subscription_id})

        {:ok, %{state | pending_requests: pending_requests, subscriptions: subscriptions}}

      {nil, _} ->
        Logger.warning("Received SUBSCRIBED for unknown request: #{request_id}")
        {:ok, state}
    end
  end

  defp handle_event(%{subscription_id: sub_id} = event_data, state) do
    case Map.get(state.subscriptions, sub_id) do
      nil ->
        Logger.warning("Received event for unknown subscription: #{sub_id}")
        {:ok, state}

      topic ->
        Logger.debug("Received event on #{topic}: #{inspect(event_data)}")
        notify_client(state, {:event, topic, event_data})
        {:ok, state}
    end
  end

  defp notify_client(%{client_pid: nil}, _message), do: :ok
  defp notify_client(%{client_pid: pid}, message) when is_pid(pid) do
    send(pid, {:wamp, message})
  end

  defp generate_request_id do
    :erlang.unique_integer([:positive])
  end
end
