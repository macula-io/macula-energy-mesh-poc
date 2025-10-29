defmodule MaculaSdk.Wamp.Connection do
  @moduledoc """
  WebSocket connection to WAMP router (Bondy).

  Manages the WebSocket connection and WAMP session lifecycle.
  """
  use WebSockex
  require Logger
  alias MaculaSdk.Wamp.Protocol

  @default_url "ws://localhost:18082/ws"
  @default_realm "com.example.realm"

  defmodule State do
    @moduledoc false
    defstruct [
      :url,
      :realm,
      :api_key,
      :username,
      :password,
      :session_id,
      :status,
      :pending_requests,
      :subscriptions,
      :registrations,    # %{registration_id => procedure}
      :client_pid
    ]
  end

  # Helper Functions

  defp generate_request_id do
    :erlang.unique_integer([:positive])
  end

  # Client API

  @doc """
  Start a WAMP connection.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (default: com.example.realm)
  - `:api_key` - API key for MaculaOs authentication (optional)
  - `:username` - Username for WAMP-CRA authentication (optional)
  - `:password` - Password for WAMP-CRA authentication (optional)
  - `:client_pid` - PID to send messages to (optional)
  """
  def start_link(opts \\ []) do
    url = Keyword.get(opts, :url, @default_url)
    realm = Keyword.get(opts, :realm, @default_realm)
    api_key = Keyword.get(opts, :api_key)
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)
    client_pid = Keyword.get(opts, :client_pid)

    state = %State{
      url: url,
      realm: realm,
      api_key: api_key,
      username: username,
      password: password,
      status: :connecting,
      pending_requests: %{},
      subscriptions: %{},
      registrations: %{},
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
  Call a remote procedure (RPC).

  Returns the request_id which can be used to track the call.
  """
  def call(pid, procedure, args \\ [], kwargs \\ %{}, options \\ %{}) do
    request_id = generate_request_id()
    WebSockex.cast(pid, {:call, request_id, procedure, args, kwargs, options})
    request_id
  end

  @doc """
  Register a procedure for RPC.

  Returns the request_id which can be used to track the registration.
  """
  def register(pid, procedure, options \\ %{}) do
    request_id = generate_request_id()
    WebSockex.cast(pid, {:register, request_id, procedure, options})
    request_id
  end

  @doc """
  Yield (return) a result from an RPC invocation.
  """
  def yield(pid, invocation_request_id, result) do
    WebSockex.cast(pid, {:yield, invocation_request_id, result})
  end

  @doc """
  Yield an error from an RPC invocation.
  """
  def yield_error(pid, invocation_request_id, error_uri, args \\ [], kwargs \\ %{}) do
    WebSockex.cast(pid, {:yield_error, invocation_request_id, error_uri, args, kwargs})
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
    # Build HELLO message details
    details = %{
      "roles" => %{
        "publisher" => %{},
        "subscriber" => %{},
        "caller" => %{},
        "callee" => %{}
      }
    }

    # Choose authentication method based on provided credentials
    {details, authmethods} = cond do
      # API key authentication (MaculaOs)
      state.api_key ->
        details_with_auth = Map.put(details, "authextra", %{"macula_apikey" => state.api_key})
        {details_with_auth, ["macula-apikey"]}

      # WAMP-CRA authentication (temporarily disabled - signature computation issue)
      # state.username && state.password ->
      #   details_with_auth = Map.put(details, "authid", state.username)
      #   {details_with_auth, ["wampcra"]}

      # Anonymous authentication (temporary workaround)
      true ->
        {details, ["anonymous"]}
    end

    details = Map.put(details, "authmethods", authmethods)

    hello = Protocol.hello_message(state.realm, details)

    encoded = Protocol.encode(hello)
    Logger.info("Sending HELLO to #{state.realm} (auth: #{hd(authmethods)})")
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

  def handle_cast({:call, request_id, procedure, args, kwargs, options}, state) do
    case state.status do
      :connected ->
        message = Protocol.call_message(request_id, procedure, args, kwargs, options)
        frame = {:text, Protocol.encode(message)}

        new_state = put_in(state.pending_requests[request_id], {:call, procedure})
        {:reply, frame, new_state}

      _ ->
        Logger.warning("Cannot call RPC: not connected")
        {:ok, state}
    end
  end

  def handle_cast({:register, request_id, procedure, options}, state) do
    case state.status do
      :connected ->
        message = Protocol.register_message(request_id, procedure, options)
        frame = {:text, Protocol.encode(message)}

        new_state = put_in(state.pending_requests[request_id], {:register, procedure})
        {:reply, frame, new_state}

      _ ->
        Logger.warning("Cannot register RPC: not connected")
        {:ok, state}
    end
  end

  def handle_cast({:yield, invocation_request_id, result}, state) do
    case state.status do
      :connected ->
        # result can be either a map with :args and :kwargs, or just args
        {args, kwargs} = case result do
          %{args: a, kwargs: k} -> {a, k}
          %{args: a} -> {a, %{}}
          args when is_list(args) -> {args, %{}}
          other -> {[other], %{}}
        end

        message = Protocol.yield_message(invocation_request_id, args, kwargs)
        frame = {:text, Protocol.encode(message)}
        {:reply, frame, state}

      _ ->
        Logger.warning("Cannot yield: not connected")
        {:ok, state}
    end
  end

  def handle_cast({:yield_error, invocation_request_id, error_uri, args, kwargs}, state) do
    case state.status do
      :connected ->
        message = Protocol.error_message(:invocation, invocation_request_id, error_uri, args, kwargs)
        frame = {:text, Protocol.encode(message)}
        {:reply, frame, state}

      _ ->
        Logger.warning("Cannot yield error: not connected")
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

      {:challenge, %{authmethod: "wampcra", extra: extra}} ->
        Logger.info("Received WAMP-CRA CHALLENGE")
        handle_wampcra_challenge(extra, state)

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

      {:registered, %{request_id: request_id, registration_id: registration_id}} ->
        handle_registered(request_id, registration_id, state)

      {:result, %{request_id: request_id} = result_data} ->
        handle_result(request_id, result_data, state)

      {:invocation, invocation_data} ->
        handle_invocation(invocation_data, state)

      {:error, error_data} ->
        handle_error(error_data, state)

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

  defp handle_registered(request_id, registration_id, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{:register, procedure}, pending_requests} ->
        Logger.info("Registered procedure #{procedure}, registration_id: #{registration_id}")

        registrations = Map.put(state.registrations, registration_id, procedure)
        notify_client(state, {:registered, procedure, registration_id})

        {:ok, %{state | pending_requests: pending_requests, registrations: registrations}}

      {nil, _} ->
        Logger.warning("Received REGISTERED for unknown request: #{request_id}")
        {:ok, state}
    end
  end

  defp handle_result(request_id, result_data, state) do
    case Map.pop(state.pending_requests, request_id) do
      {{:call, procedure}, pending_requests} ->
        Logger.debug("Received RESULT for #{procedure}: #{inspect(result_data)}")

        notify_client(state, {:result, request_id, result_data})

        {:ok, %{state | pending_requests: pending_requests}}

      {nil, _} ->
        Logger.warning("Received RESULT for unknown request: #{request_id}")
        {:ok, state}
    end
  end

  defp handle_invocation(invocation_data, state) do
    %{
      invocation_request_id: invocation_request_id,
      registration_id: registration_id,
      details: details,
      args: args,
      kwargs: kwargs
    } = invocation_data

    case Map.get(state.registrations, registration_id) do
      nil ->
        Logger.warning("Received INVOCATION for unknown registration: #{registration_id}")
        {:ok, state}

      _procedure ->
        Logger.debug("Received INVOCATION for registration #{registration_id}")
        notify_client(state, {:invocation, invocation_request_id, registration_id, details, args, kwargs})
        {:ok, state}
    end
  end

  defp handle_error(error_data, state) do
    %{
      request_type: request_type,
      request_id: request_id,
      error_uri: error_uri
    } = error_data

    args = Map.get(error_data, :args, [])
    kwargs = Map.get(error_data, :kwargs, %{})

    Logger.error("WAMP ERROR (#{request_type}): #{error_uri} for request_id: #{request_id}")
    Logger.debug("Error details - args: #{inspect(args)}, kwargs: #{inspect(kwargs)}")

    # Remove from pending requests if it exists
    {_value, pending_requests} = Map.pop(state.pending_requests, request_id)

    # Notify client about the error
    notify_client(state, {:error, request_type, request_id, error_uri, args, kwargs})

    {:ok, %{state | pending_requests: pending_requests}}
  end

  defp handle_wampcra_challenge(extra, state) do
    # Extract challenge string from extra
    challenge = Map.get(extra, "challenge", "")

    if state.password do
      # Compute WAMP-CRA signature
      signature = Protocol.compute_wampcra_signature(challenge, state.password)

      # Send AUTHENTICATE message
      auth_message = Protocol.authenticate_message(signature)
      encoded = Protocol.encode(auth_message)

      Logger.info("Sending WAMP-CRA AUTHENTICATE")
      Logger.info("Challenge: #{String.slice(challenge, 0, 50)}..., Password: #{String.slice(state.password, 0, 5)}..., Signature: #{String.slice(signature, 0, 20)}...")

      frame = {:text, encoded}
      {:reply, frame, state}
    else
      Logger.error("Received CHALLENGE but no password configured")
      {:close, state}
    end
  end

  defp notify_client(%{client_pid: nil}, _message), do: :ok
  defp notify_client(%{client_pid: pid}, message) when is_pid(pid) do
    send(pid, {:wamp, message})
  end
end
