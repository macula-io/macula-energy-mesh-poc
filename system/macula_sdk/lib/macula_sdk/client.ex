defmodule MaculaSdk.Client do
  @moduledoc """
  Elixir wrapper for the Erlang macula_sdk (HTTP/3).

  Provides compatibility layer for migrating from WAMP to HTTP/3.
  Maintains similar API to the legacy MaculaSdk.Wamp.Client but uses
  the new macula_sdk Erlang module under the hood.

  ## Migration from WAMP

  This module provides a drop-in replacement for MaculaSdk.Wamp.Client:

      # Old WAMP code:
      {:ok, client} = MaculaSdk.Wamp.Client.start_link(
        url: "ws://localhost:18082/ws",
        realm: "be.cortexiq.energy"
      )

      # New HTTP/3 code:
      {:ok, client} = MaculaSdk.Client.start_link(
        url: "https://localhost:9443",
        realm: "be.cortexiq.energy"
      )

  The API is identical - only the transport changed (WAMP → HTTP/3).
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :client_pid,          # Erlang :macula_sdk_client process
      :url,
      :realm,
      :status,
      :subscriptions        # %{topic => {ref, handler_fun}}
    ]
  end

  ## Client API

  @doc """
  Start a Macula HTTP/3 client.

  ## Options
  - `:url` - HTTPS URL (e.g., "https://localhost:9443")
  - `:realm` - Realm to connect to (e.g., "be.cortexiq.energy")
  - `:name` - GenServer name (optional)

  ## Examples

      {:ok, client} = MaculaSdk.Client.start_link(
        url: "https://localhost:9443",
        realm: "be.cortexiq.energy"
      )
  """
  def start_link(opts \\ []) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, client_opts, gen_opts)
  end

  @doc """
  Publish a message to a topic.

  ## Parameters
  - `client` - Client PID
  - `topic` - Topic name (binary)
  - `args` - List of positional arguments (for WAMP compatibility, unused in HTTP/3)
  - `kwargs` - Map of keyword arguments (the actual event data)
  - `options` - Publish options (e.g., qos, retain)

  ## Examples

      # Publish with kwargs (standard pattern)
      MaculaSdk.Client.publish(client, "be.cortexiq.simulation.time_advanced", [], %{
        simulation_time: ~U[2025-06-15 14:32:00Z],
        speed: 105_120
      })

      # With options
      MaculaSdk.Client.publish(client, "my.topic", [], %{data: "value"}, %{qos: 1})
  """
  def publish(client, topic, args \\ [], kwargs \\ %{}, options \\ %{}) do
    GenServer.call(client, {:publish, topic, args, kwargs, options}, 30_000)
  end

  @doc """
  Subscribe to a topic with a handler function.

  The handler function receives `(topic, event_data)` where event_data
  contains `:args` and `:kwargs` keys for WAMP compatibility.

  ## Examples

      MaculaSdk.Client.subscribe(client, "be.cortexiq.simulation.time_advanced", fn topic, event_data ->
        kwargs = Map.get(event_data, :kwargs, %{})
        Logger.info("Time advanced: \#{inspect(kwargs)}")
      end)
  """
  def subscribe(client, topic, handler_fun, options \\ %{}) do
    GenServer.call(client, {:subscribe, topic, handler_fun, options}, 30_000)
  end

  @doc """
  Register a procedure (RPC endpoint).

  The handler function receives `(args, kwargs, details)` and should return
  `{:ok, result}` or `{:error, reason}`.

  ## Examples

      MaculaSdk.Client.register(client, "my.app.get_user", fn _args, kwargs, _details ->
        user_id = Map.get(kwargs, "user_id")
        {:ok, %{name: "Alice", id: user_id}}
      end)
  """
  def register(client, procedure, handler_fun, options \\ %{}) do
    GenServer.call(client, {:register, procedure, handler_fun, options}, 30_000)
  end

  @doc """
  Call a remote procedure (RPC).

  Returns `{:ok, result}` or `{:error, reason}`.

  ## Examples

      {:ok, result} = MaculaSdk.Client.call(client, "my.app.get_user", [], %{user_id: "123"})
  """
  def call(client, procedure, args \\ [], kwargs \\ %{}, options \\ %{}) do
    GenServer.call(client, {:call, procedure, args, kwargs, options}, 30_000)
  end

  @doc """
  Get client status.

  Returns `:connected`, `:connecting`, `:disconnected`, or `:error`.
  """
  def status(client) do
    GenServer.call(client, :status, 30_000)
  end

  @doc """
  Stop the client.
  """
  def stop(client) do
    GenServer.stop(client, :normal)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url) |> to_string()
    realm = Keyword.fetch!(opts, :realm) |> to_string()

    # Convert to Erlang types
    erl_url = String.to_charlist(url)
    erl_opts = %{realm: String.to_charlist(realm)}

    # Connect using Erlang macula_sdk
    case :macula_sdk.connect(erl_url, erl_opts) do
      {:ok, client_pid} ->
        Logger.info("MaculaSdk.Client connected to #{url} realm #{realm}")

        state = %State{
          client_pid: client_pid,
          url: url,
          realm: realm,
          status: :connected,
          subscriptions: %{}
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error("MaculaSdk.Client failed to connect: #{inspect(reason)}")
        {:stop, {:connection_failed, reason}}
    end
  end

  @impl true
  def handle_call({:publish, topic, _args, kwargs, options}, _from, state) do
    # Convert topic to binary
    erl_topic = String.to_charlist(to_string(topic))

    # Convert options
    erl_opts = convert_publish_options(options)

    # Publish using Erlang SDK
    result = :macula_sdk.publish(state.client_pid, erl_topic, kwargs, erl_opts)

    case result do
      :ok ->
        {:reply, :ok, state}

      {:error, reason} ->
        Logger.error("Publish failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:subscribe, topic, handler_fun, _options}, _from, state) do
    # Convert topic to binary
    erl_topic = String.to_charlist(to_string(topic))

    # Create wrapper callback that adapts Erlang callback to Elixir
    callback = fn event_data ->
      # Convert to WAMP-style format for compatibility
      formatted_data = %{
        args: [],
        kwargs: event_data
      }

      # Call the handler
      handler_fun.(to_string(topic), formatted_data)
    end

    # Subscribe using Erlang SDK
    case :macula_sdk.subscribe(state.client_pid, erl_topic, callback) do
      {:ok, ref} ->
        # Store subscription
        subscriptions = Map.put(state.subscriptions, topic, {ref, handler_fun})
        {:reply, :ok, %{state | subscriptions: subscriptions}}

      {:error, reason} ->
        Logger.error("Subscribe failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:register, procedure, handler_fun, _options}, _from, state) do
    # Convert procedure to binary
    erl_procedure = String.to_charlist(to_string(procedure))

    # Create wrapper callback that adapts Erlang callback to Elixir
    callback = fn args, kwargs, details ->
      # Call the handler
      handler_fun.(args, kwargs, details)
    end

    # Register using Erlang SDK
    case :macula_sdk.register(state.client_pid, erl_procedure, callback) do
      :ok ->
        {:reply, :ok, state}

      {:ok, registration_id} ->
        {:reply, {:ok, registration_id}, state}

      {:error, reason} ->
        Logger.error("Register failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:call, procedure, _args, kwargs, options}, _from, state) do
    # Convert procedure to binary
    erl_procedure = String.to_charlist(to_string(procedure))

    # Convert options (extract timeout if present)
    timeout = Map.get(options, :timeout, 30000)
    erl_opts = %{timeout: timeout}

    # Call using Erlang SDK
    result = :macula_sdk.call(state.client_pid, erl_procedure, kwargs, erl_opts)

    {:reply, result, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def terminate(_reason, state) do
    # Disconnect
    if state.client_pid do
      :macula_sdk.disconnect(state.client_pid)
    end

    :ok
  end

  ## Private Functions

  defp convert_publish_options(options) when is_map(options) do
    options
    |> Enum.reduce(%{}, fn
      {:qos, qos}, acc -> Map.put(acc, :qos, qos)
      {:retain, retain}, acc -> Map.put(acc, :retain, retain)
      {:acknowledge, ack}, acc -> Map.put(acc, :acknowledge, ack)
      _, acc -> acc
    end)
  end

  defp convert_publish_options(_), do: %{}
end
