defmodule MeshWamp.Client do
  @moduledoc """
  High-level WAMP client interface.

  Manages connection to WAMP router and provides simple API for pub/sub.
  """
  use GenServer
  require Logger
  alias MeshWamp.Connection

  defmodule State do
    @moduledoc false
    defstruct [
      :connection_pid,
      :url,
      :realm,
      :status,
      :session_id,
      :event_handlers
    ]
  end

  # Client API

  @doc """
  Start a WAMP client.

  ## Options
  - `:url` - WebSocket URL (default: ws://localhost:18082/ws)
  - `:realm` - WAMP realm to join (default: com.example.realm)
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
    GenServer.call(client, {:publish, topic, args, kwargs, options})
  end

  @doc """
  Subscribe to a topic with a handler function.

  Handler function receives: topic, event_data
  """
  def subscribe(client, topic, handler_fun, options \\ %{}) do
    GenServer.call(client, {:subscribe, topic, handler_fun, options})
  end

  @doc """
  Get client status.
  """
  def status(client) do
    GenServer.call(client, :status)
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

    state = %State{
      url: url,
      realm: realm,
      status: :connecting,
      event_handlers: %{}
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case Connection.start_link(
           url: state.url,
           realm: state.realm,
           client_pid: self()
         ) do
      {:ok, pid} ->
        Process.monitor(pid)
        {:noreply, %{state | connection_pid: pid}}

      {:error, reason} ->
        Logger.error("Failed to connect: #{inspect(reason)}")
        {:stop, reason, state}
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
      {nil, handlers} ->
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
