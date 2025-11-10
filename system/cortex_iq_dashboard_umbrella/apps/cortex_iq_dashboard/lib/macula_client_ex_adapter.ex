defmodule MaculaClientEx.Client do
  @moduledoc """
  Minimal adapter for MaculaClientEx.Client API.

  Provides compatibility layer for code that was written for MaculaClientEx.Client
  but now uses the macula Erlang package directly.

  This is a thin wrapper - just delegates to :macula_sdk Erlang module.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [:client_pid, :url, :realm, :status]
  end

  ## Client API

  def start_link(opts \\ []) do
    {gen_opts, client_opts} = Keyword.split(opts, [:name])
    GenServer.start_link(__MODULE__, client_opts, gen_opts)
  end

  def publish(client, topic, _args \\ [], kwargs \\ %{}, options \\ %{}) do
    GenServer.call(client, {:publish, topic, kwargs, options}, 30_000)
  end

  def subscribe(client, topic, handler_fun, _options \\ %{}) do
    GenServer.call(client, {:subscribe, topic, handler_fun}, 30_000)
  end

  def register(client, procedure, handler_fun, _options \\ %{}) do
    GenServer.call(client, {:register, procedure, handler_fun}, 30_000)
  end

  def call(client, procedure, _args \\ [], kwargs \\ %{}, options \\ %{}) do
    GenServer.call(client, {:call, procedure, kwargs, options}, 30_000)
  end

  def status(client) do
    GenServer.call(client, :status, 30_000)
  end

  def stop(client) do
    GenServer.stop(client, :normal)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url) |> to_string() |> String.to_charlist()
    realm = Keyword.fetch!(opts, :realm) |> to_string() |> String.to_charlist()

    erl_opts = %{realm: realm}

    case :macula_sdk.connect(url, erl_opts) do
      {:ok, client_pid} ->
        {:ok, %State{client_pid: client_pid, url: url, realm: realm, status: :connected}}
      {:error, reason} ->
        {:stop, {:connection_failed, reason}}
    end
  end

  @impl true
  def handle_call({:publish, topic, kwargs, _options}, _from, state) do
    erl_topic = String.to_charlist(to_string(topic))
    result = :macula_sdk.publish(state.client_pid, erl_topic, kwargs, %{})
    {:reply, result, state}
  end

  @impl true
  def handle_call({:subscribe, topic, handler_fun}, _from, state) do
    erl_topic = String.to_charlist(to_string(topic))

    callback = fn event_data ->
      formatted_data = %{args: [], kwargs: event_data}
      handler_fun.(to_string(topic), formatted_data)
    end

    case :macula_sdk.subscribe(state.client_pid, erl_topic, callback) do
      {:ok, _ref} -> {:reply, :ok, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:register, procedure, handler_fun}, _from, state) do
    erl_procedure = String.to_charlist(to_string(procedure))

    callback = fn args, kwargs, details ->
      handler_fun.(args, kwargs, details)
    end

    result = :macula_sdk.register(state.client_pid, erl_procedure, callback)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:call, procedure, kwargs, options}, _from, state) do
    erl_procedure = String.to_charlist(to_string(procedure))
    timeout = Map.get(options, :timeout, 30000)
    erl_opts = %{timeout: timeout}

    result = :macula_sdk.call(state.client_pid, erl_procedure, kwargs, erl_opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.client_pid do
      :macula_sdk.disconnect(state.client_pid)
    end
    :ok
  end
end
