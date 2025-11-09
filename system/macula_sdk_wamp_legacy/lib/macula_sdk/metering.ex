defmodule MaculaSdk.Metering do
  @moduledoc """
  Tracks WAMP operation usage per API key for billing/monitoring.

  Records:
  - PUBLISH operations
  - SUBSCRIBE operations
  - CALL operations (RPC)

  Exposes metrics via Telemetry for Prometheus export.
  """
  use GenServer
  require Logger

  @table_name :macula_metering

  defstruct [:table]

  ## Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a WAMP operation for an API key.

  ## Examples

      iex> record("myapp-service-123", :publish, "myapp.events.user.created")
      :ok

      iex> record("myapp-service-123", :subscribe, "myapp.events.*")
      :ok
  """
  def record(api_key, operation, topic \\ nil) do
    GenServer.cast(__MODULE__, {:record, api_key, operation, topic})
  end

  @doc """
  Gets usage statistics for an API key.

  Returns map: %{publish: count, subscribe: count, call: count}
  """
  def get_stats(api_key) do
    GenServer.call(__MODULE__, {:get_stats, api_key})
  end

  @doc """
  Gets all usage statistics (for admin/monitoring).

  Returns list of {api_key, stats} tuples.
  """
  def get_all_stats do
    GenServer.call(__MODULE__, :get_all_stats)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("Starting MaculaOs Metering")

    # Create ETS table for fast concurrent access
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    # Initialize telemetry metrics
    init_telemetry()

    {:ok, %__MODULE__{table: table}}
  end

  @impl true
  def handle_cast({:record, api_key, operation, topic}, state) do
    # Increment counter in ETS
    key = {api_key, operation}

    :ets.update_counter(@table_name, key, {2, 1}, {key, 0})

    # Emit telemetry event
    :telemetry.execute(
      [:macula_os, :proxy, :operation],
      %{count: 1},
      %{api_key: api_key, operation: operation, topic: topic}
    )

    {:noreply, state}
  end

  @impl true
  def handle_call({:get_stats, api_key}, _from, state) do
    stats = %{
      publish: get_count(api_key, :publish),
      subscribe: get_count(api_key, :subscribe),
      call: get_count(api_key, :call)
    }

    {:reply, stats, state}
  end

  def handle_call(:get_all_stats, _from, state) do
    # Group by API key
    all_records = :ets.tab2list(@table_name)

    stats = Enum.reduce(all_records, %{}, fn {{api_key, operation}, count}, acc ->
      api_stats = Map.get(acc, api_key, %{publish: 0, subscribe: 0, call: 0})
      api_stats = Map.put(api_stats, operation, count)
      Map.put(acc, api_key, api_stats)
    end)

    stats_list = Enum.map(stats, fn {api_key, stats} -> {api_key, stats} end)

    {:reply, stats_list, state}
  end

  ## Private Functions

  defp get_count(api_key, operation) do
    case :ets.lookup(@table_name, {api_key, operation}) do
      [{{^api_key, ^operation}, count}] -> count
      [] -> 0
    end
  end

  defp init_telemetry do
    # Register telemetry handlers for logging
    :telemetry.attach(
      "macula-os-metering-logger",
      [:macula_os, :proxy, :operation],
      &handle_telemetry_event/4,
      nil
    )
  end

  defp handle_telemetry_event(
    [:macula_os, :proxy, :operation],
    measurements,
    metadata,
    _config
  ) do
    Logger.debug(
      "WAMP #{metadata.operation}: #{metadata.topic || "N/A"} (API key: #{String.slice(metadata.api_key, 0..7)}...)",
      measurements: measurements
    )
  end
end
