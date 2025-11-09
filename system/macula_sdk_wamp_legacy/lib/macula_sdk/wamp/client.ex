defmodule MaculaSdk.Wamp.Client do
  @moduledoc """
  High-level WAMP client interface.

  Manages connection to WAMP router and provides simple API for pub/sub.
  """
  use GenServer
  require Logger
  alias MaculaSdk.Wamp.Connection

  defmodule State do
    @moduledoc false
    defstruct [
      :connection_pid,
      :url,
      :realm,
      :api_key,
      :username,
      :password,
      :status,
      :session_id,
      :event_handlers,
      :rpc_handlers,     # %{registration_id => handler_fun}
      :pending_calls,    # %{request_id => from}
      :retry_count,
      :consecutive_failures,  # Track failures for circuit breaker
      :max_retries,           # Max retry attempts before giving up
      :last_abort_reason      # Last ABORT reason for retry decision
    ]
  end

  # Client API

  @doc """
  Start a WAMP client.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (default: com.example.realm)
  - `:api_key` - API key for MaculaOs authentication (optional)
  - `:username` - Username for WAMP-CRA authentication (optional)
  - `:password` - Password for WAMP-CRA authentication (optional)
  - `:max_retries` - Maximum retry attempts before giving up (default: 20)
  - `:name` - GenServer name (optional)
  """
  def start_link(opts \\ []) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, client_opts, gen_opts)
  end

  @doc """
  Publish a message to a topic.
  """
  def publish(client, topic, args \\ [], kwargs \\ %{}, options \\ %{}) do
    # Use 30 second timeout to handle high connection load
    GenServer.call(client, {:publish, topic, args, kwargs, options}, 30_000)
  end

  @doc """
  Subscribe to a topic with a handler function.

  Handler function receives: topic, event_data
  """
  def subscribe(client, topic, handler_fun, options \\ %{}) do
    # Use 30 second timeout to handle high connection load
    GenServer.call(client, {:subscribe, topic, handler_fun, options}, 30_000)
  end

  @doc """
  Call a remote procedure (RPC).

  Returns `{:ok, result}` or `{:error, reason}`.
  Handler function receives: args, kwargs
  """
  def call(client, procedure, args \\ [], kwargs \\ %{}, options \\ %{}) do
    # Use 30 second timeout for RPC calls
    GenServer.call(client, {:call, procedure, args, kwargs, options}, 30_000)
  end

  @doc """
  Register a procedure for RPC.

  Handler function receives: args, kwargs, details
  Handler should return: {:ok, result} or {:error, error_uri, args, kwargs}
  """
  def register(client, procedure, handler_fun, options \\ %{}) do
    # Use 30 second timeout to handle high connection load
    GenServer.call(client, {:register, procedure, handler_fun, options}, 30_000)
  end

  @doc """
  Get client status.
  """
  def status(client) do
    GenServer.call(client, :status, 30_000)
  end

  @doc """
  Stop the client.
  """
  def stop(client) do
    GenServer.stop(client)
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    url = Keyword.get(opts, :url, "ws://localhost:18082/ws")
    realm = Keyword.get(opts, :realm, "com.example.realm")
    api_key = Keyword.get(opts, :api_key)
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)
    max_retries = Keyword.get(opts, :max_retries, 20)

    state = %State{
      url: url,
      realm: realm,
      api_key: api_key,
      username: username,
      password: password,
      status: :connecting,
      event_handlers: %{},
      rpc_handlers: %{},
      pending_calls: %{},
      retry_count: 0,
      consecutive_failures: 0,
      max_retries: max_retries,
      last_abort_reason: nil
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    # Check if we've exceeded max retries
    if state.retry_count >= state.max_retries do
      Logger.error(
        "MaculaSdk.Wamp.Client: Max retries (#{state.max_retries}) exceeded. Giving up."
      )
      {:stop, :max_retries_exceeded, state}
    else
      case Connection.start_link(
             url: state.url,
             realm: state.realm,
             api_key: state.api_key,
             username: state.username,
             password: state.password,
             client_pid: self()
           ) do
        {:ok, pid} ->
          Process.monitor(pid)
          Logger.info("MaculaSdk.Wamp.Client: Connection established successfully")

          # Reset failure counters on successful connection
          {:noreply, %{state |
            connection_pid: pid,
            retry_count: 0,
            consecutive_failures: 0,
            last_abort_reason: nil
          }}

        {:error, reason} ->
          schedule_retry(state, reason)
      end
    end
  end

  # Calculate retry delay with exponential backoff + jitter + circuit breaker
  defp schedule_retry(state, reason) do
    # Base exponential backoff: 1s, 2s, 4s, 8s, 16s, 30s (capped)
    base_delay = min(1000 * :math.pow(2, state.retry_count), 30_000) |> round()

    # Circuit breaker: If many consecutive failures, add extra delay
    circuit_breaker_penalty =
      if state.consecutive_failures > 5 do
        # After 5 consecutive failures, add extra 10-30 seconds
        :rand.uniform(20_000) + 10_000
      else
        0
      end

    # Add jitter: ±25% randomization to prevent thundering herd
    jitter = :rand.uniform(round(base_delay * 0.5)) - round(base_delay * 0.25)

    retry_delay = base_delay + jitter + circuit_breaker_penalty

    Logger.warning(
      "MaculaSdk.Wamp.Client: Failed to connect: #{inspect(reason)}. " <>
      "Retrying in #{retry_delay}ms (attempt #{state.retry_count + 1}/#{state.max_retries}, " <>
      "consecutive failures: #{state.consecutive_failures + 1})"
    )

    Process.send_after(self(), :retry_connect, retry_delay)

    {:noreply, %{state |
      status: :disconnected,
      retry_count: state.retry_count + 1,
      consecutive_failures: state.consecutive_failures + 1
    }}
  end

  @impl true
  def handle_call({:publish, topic, args, kwargs, options}, _from, state) do
    case state.status do
      :connected ->
        Connection.publish(state.connection_pid, topic, args, kwargs, options)
        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:subscribe, topic, handler_fun, options}, _from, state) do
    case state.status do
      :connected ->
        Connection.subscribe(state.connection_pid, topic, options)

        # Store handler function for this topic
        handlers = Map.put(state.event_handlers, topic, handler_fun)
        {:reply, :ok, %{state | event_handlers: handlers}}

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:call, procedure, args, kwargs, options}, from, state) do
    case state.status do
      :connected ->
        request_id = Connection.call(state.connection_pid, procedure, args, kwargs, options)

        # Store the caller's pid to reply later when we receive RESULT
        pending = Map.put(state.pending_calls, request_id, from)
        {:noreply, %{state | pending_calls: pending}}

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call({:register, procedure, handler_fun, options}, _from, state) do
    case state.status do
      :connected ->
        Connection.register(state.connection_pid, procedure, options)

        # Store handler function temporarily by procedure name
        # Will move to registration_id when we receive REGISTERED
        handlers = Map.put(state.rpc_handlers, procedure, handler_fun)
        {:reply, :ok, %{state | rpc_handlers: handlers}}

      _ ->
        {:reply, {:error, :not_connected}, state}
    end
  end

  def handle_call(:status, _from, state) do
    {:reply, %{status: state.status, session_id: state.session_id}, state}
  end

  @impl true
  def handle_info({:wamp, {:connected, session_id}}, state) do
    Logger.info("WAMP client connected, session: #{session_id}")

    # Reset retry counters on successful session establishment
    {:noreply, %{state |
      status: :connected,
      session_id: session_id,
      retry_count: 0,
      consecutive_failures: 0,
      last_abort_reason: nil
    }}
  end

  def handle_info({:wamp, {:published, topic, publication_id}}, state) do
    Logger.debug("Published to #{topic}, pub_id: #{publication_id}")
    {:noreply, state}
  end

  def handle_info({:wamp, {:subscribed, topic, subscription_id}}, state) do
    Logger.info("Subscribed to #{topic}, sub_id: #{subscription_id}")

    # Move handler from topic-based key to subscription_id-based key
    case Map.pop(state.event_handlers, topic) do
      {nil, _} ->
        Logger.warning("No handler found for subscribed topic: #{topic}")
        Logger.warning("Pending topic handlers: #{inspect(Map.keys(state.event_handlers))}")
        {:noreply, state}

      {handler_fun, handlers} ->
        # Store handler by subscription_id instead of topic
        handlers = Map.put(handlers, subscription_id, handler_fun)
        Logger.info("Mapped handler: subscription_id #{subscription_id} → topic #{topic}")
        Logger.debug("Active subscription_ids: #{inspect(Map.keys(handlers))}")
        {:noreply, %{state | event_handlers: handlers}}
    end
  end

  def handle_info({:wamp, {:event, topic, event_data}}, state) do
    # event_data contains subscription_id - use it to find the handler
    subscription_id = Map.get(event_data, :subscription_id)

    Logger.info("Client received EVENT: topic=#{topic}, subscription_id=#{subscription_id}")

    case Map.get(state.event_handlers, subscription_id) do
      nil ->
        Logger.warning("No handler for subscription_id: #{subscription_id}, topic: #{topic}")
        Logger.warning("Available handlers: #{inspect(Map.keys(state.event_handlers))}")
        {:noreply, state}

      handler_fun when is_function(handler_fun) ->
        Logger.debug("Invoking event handler for topic: #{topic}")
        try do
          handler_fun.(topic, event_data)
          Logger.debug("Event handler completed for topic: #{topic}")
        rescue
          error ->
            Logger.error("Error in event handler for #{topic}: #{inspect(error)}")
            Logger.error("Stacktrace: #{inspect(__STACKTRACE__)}")
        end

        {:noreply, state}
    end
  end

  def handle_info({:wamp, {:registered, procedure, registration_id}}, state) do
    Logger.info("Registered RPC procedure: #{procedure}, registration_id: #{registration_id}")

    # Move handler from procedure name to registration_id
    case Map.pop(state.rpc_handlers, procedure) do
      {nil, _} ->
        Logger.warning("No handler found for registered procedure: #{procedure}")
        {:noreply, state}

      {handler_fun, handlers} ->
        handlers = Map.put(handlers, registration_id, handler_fun)
        {:noreply, %{state | rpc_handlers: handlers}}
    end
  end

  def handle_info({:wamp, {:result, request_id, result}}, state) do
    Logger.debug("Received RPC RESULT for request_id: #{request_id}")

    # Find the waiting caller and reply
    case Map.pop(state.pending_calls, request_id) do
      {nil, _} ->
        Logger.warning("No pending call for request_id: #{request_id}")
        {:noreply, state}

      {from, pending} ->
        GenServer.reply(from, {:ok, result})
        {:noreply, %{state | pending_calls: pending}}
    end
  end

  def handle_info({:wamp, {:invocation, invocation_request_id, registration_id, details, args, kwargs}}, state) do
    Logger.debug("Received RPC INVOCATION for registration_id: #{registration_id}")

    # Find the handler function and invoke it
    case Map.get(state.rpc_handlers, registration_id) do
      nil ->
        Logger.warning("No RPC handler for registration_id: #{registration_id}")
        # Send error result
        Connection.yield_error(state.connection_pid, invocation_request_id, "wamp.error.no_such_procedure")
        {:noreply, state}

      handler_fun when is_function(handler_fun) ->
        # Call the handler function
        try do
          result = handler_fun.(args, kwargs, details)

          case result do
            {:ok, result_data} ->
              Connection.yield(state.connection_pid, invocation_request_id, result_data)

            {:error, error_uri, error_args, error_kwargs} ->
              Connection.yield_error(state.connection_pid, invocation_request_id, error_uri, error_args, error_kwargs)

            {:error, error_uri} ->
              Connection.yield_error(state.connection_pid, invocation_request_id, error_uri)
          end
        rescue
          error ->
            Logger.error("Error in RPC handler for registration #{registration_id}: #{inspect(error)}")
            Connection.yield_error(state.connection_pid, invocation_request_id, "wamp.error.runtime_error")
        end

        {:noreply, state}
    end
  end

  def handle_info({:wamp, {:error, request_type, request_id, error_uri, _args, kwargs}}, state) do
    Logger.error("WAMP ERROR (#{request_type}): #{error_uri} for request_id: #{request_id}")

    # Store ABORT reason for retry decision making
    new_state = case request_type do
      :session -> %{state | last_abort_reason: error_uri}
      _ -> state
    end

    # If this was a CALL, reply to the caller with error
    case Map.pop(new_state.pending_calls, request_id) do
      {nil, _} ->
        # Not a pending call, might be a REGISTER or SUBSCRIBE error
        # Check if it's an ABORT during session establishment
        if request_type == :session do
          # Log human-readable message from ABORT if available
          abort_message = Map.get(kwargs, "message", error_uri)
          Logger.error("WAMP ABORT during session: #{abort_message}")
        end

        {:noreply, new_state}

      {from, pending} ->
        GenServer.reply(from, {:error, error_uri})
        {:noreply, %{new_state | pending_calls: pending}}
    end
  end

  def handle_info(:retry_connect, state) do
    Logger.info("MaculaSdk.Wamp.Client: Retrying connection...")
    {:noreply, state, {:continue, :connect}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{connection_pid: pid} = state) do
    Logger.error("Connection process down: #{inspect(reason)}")

    # Don't give up immediately - attempt reconnection
    # This handles unexpected disconnections (Bondy restart, network issues, etc.)
    new_state = %{state |
      status: :disconnected,
      connection_pid: nil,
      session_id: nil,
      consecutive_failures: state.consecutive_failures + 1
    }

    # Check if we should retry based on the reason
    should_retry = case reason do
      # Normal shutdowns - retry
      :normal -> true
      :shutdown -> true
      {:shutdown, _} -> true

      # Connection errors - retry
      :connection_lost -> true
      :websocket_closed -> true

      # WAMP ABORT errors - check last_abort_reason
      _ ->
        case state.last_abort_reason do
          # Temporary errors - retry
          "wamp.close.system_shutdown" -> true
          "wamp.error.timeout" -> true
          "wamp.error.network_failure" -> true

          # Permanent errors - don't retry
          "wamp.error.not_authorized" -> false
          "wamp.error.no_such_realm" -> false

          # Unknown - retry with caution
          _ -> state.consecutive_failures < 10
        end
    end

    if should_retry and state.retry_count < state.max_retries do
      Logger.info("MaculaSdk.Wamp.Client: Attempting automatic reconnection...")
      schedule_retry(new_state, reason)
    else
      Logger.error("MaculaSdk.Wamp.Client: Not retrying - reason: #{inspect(reason)}, " <>
                   "retries: #{state.retry_count}/#{state.max_retries}")
      {:stop, :connection_lost, new_state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("Unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, %{connection_pid: pid} = _state) when is_pid(pid) do
    Connection.disconnect(pid)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
