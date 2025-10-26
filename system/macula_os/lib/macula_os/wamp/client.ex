defmodule MaculaOs.Wamp.Client do
  @moduledoc """
  High-level WAMP client interface.

  Manages connection to WAMP router and provides simple API for pub/sub.
  """
  use GenServer
  require Logger
  alias MaculaOs.Wamp.Connection

  defmodule State do
    @moduledoc false
    defstruct [
      :connection_pid,
      :url,
      :realm,
      :api_key,
      :status,
      :session_id,
      :event_handlers,
      :rpc_handlers,     # %{registration_id => handler_fun}
      :pending_calls,    # %{request_id => from}
      :retry_count
    ]
  end

  # Client API

  @doc """
  Start a WAMP client.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (default: com.example.realm)
  - `:api_key` - API key for MaculaOs authentication (optional)
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

    state = %State{
      url: url,
      realm: realm,
      api_key: api_key,
      status: :connecting,
      event_handlers: %{},
      rpc_handlers: %{},
      pending_calls: %{},
      retry_count: 0
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case Connection.start_link(
           url: state.url,
           realm: state.realm,
           api_key: state.api_key,
           client_pid: self()
         ) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:noreply, %{state | connection_pid: pid, retry_count: 0}}

      {:error, reason} ->
        retry_delay = min(1000 * :math.pow(2, state.retry_count), 30_000) |> round()
        Logger.warning(
          "MaculaOs.Wamp.Client: Failed to connect: #{inspect(reason)}. " <>
          "Retrying in #{retry_delay}ms (attempt #{state.retry_count + 1})"
        )

        Process.send_after(self(), :retry_connect, retry_delay)
        {:noreply, %{state | status: :disconnected, retry_count: state.retry_count + 1}}
    end
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
    {:noreply, %{state | status: :connected, session_id: session_id}}
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
        {:noreply, state}

      {handler_fun, handlers} ->
        # Store handler by subscription_id instead of topic
        handlers = Map.put(handlers, subscription_id, handler_fun)
        {:noreply, %{state | event_handlers: handlers}}
    end
  end

  def handle_info({:wamp, {:event, topic, event_data}}, state) do
    # event_data contains subscription_id - use it to find the handler
    subscription_id = Map.get(event_data, :subscription_id)

    case Map.get(state.event_handlers, subscription_id) do
      nil ->
        Logger.warning("No handler for subscription_id: #{subscription_id}, topic: #{topic}")
        {:noreply, state}

      handler_fun when is_function(handler_fun) ->
        try do
          handler_fun.(topic, event_data)
        rescue
          error ->
            Logger.error("Error in event handler for #{topic}: #{inspect(error)}")
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

  def handle_info({:wamp, {:error, request_type, request_id, error_uri, _args, _kwargs}}, state) do
    Logger.error("WAMP ERROR (#{request_type}): #{error_uri} for request_id: #{request_id}")

    # If this was a CALL, reply to the caller with error
    case Map.pop(state.pending_calls, request_id) do
      {nil, _} ->
        # Not a pending call, might be a REGISTER or SUBSCRIBE error
        {:noreply, state}

      {from, pending} ->
        GenServer.reply(from, {:error, error_uri})
        {:noreply, %{state | pending_calls: pending}}
    end
  end

  def handle_info(:retry_connect, state) do
    Logger.info("MaculaOs.Wamp.Client: Retrying connection...")
    {:noreply, state, {:continue, :connect}}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{connection_pid: pid} = state) do
    Logger.error("Connection process down: #{inspect(reason)}")
    {:stop, :connection_lost, %{state | status: :disconnected}}
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
