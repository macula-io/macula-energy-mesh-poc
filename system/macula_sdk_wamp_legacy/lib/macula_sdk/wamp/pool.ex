defmodule MaculaSdk.Wamp.Pool do
  @moduledoc """
  WAMP client connection pool.

  Provides a shared pool of WAMP client connections to avoid creating
  thousands of individual connections for each home/process.

  ## Architecture

  Instead of:
  - 10,000 homes × 15 subscribers/publishers = 150,000 WAMP connections

  We have:
  - 1 shared pool with 20 WAMP client connections
  - All homes share the pool via checkout/checkin

  ## Usage

      # Start pool (typically in Application supervision tree)
      children = [
        {MaculaSdk.Wamp.Pool, [
          url: "ws://bondy:18080/ws",
          realm: "be.cortexiq.energy",
          pool_size: 20
        ]}
      ]

      # Use pool from any process
      MaculaSdk.Wamp.Pool.publish("my.topic", [], %{key: "value"})
      MaculaSdk.Wamp.Pool.subscribe("my.topic", fn topic, event -> ... end)

  ## Configuration

  - `:url` - WAMP router URL (required)
  - `:realm` - WAMP realm (required)
  - `:pool_size` - Number of workers in pool (default: 20)
  - `:max_overflow` - Max additional workers when pool is full (default: 10)
  - `:api_key` - API key for MaculaOs authentication (optional)
  - `:username` - Username for WAMP-CRA authentication (optional)
  - `:password` - Password for WAMP-CRA authentication (optional)
  - `:name` - Pool name (default: __MODULE__)
  """
  use Supervisor
  require Logger

  @default_pool_size 20
  @default_max_overflow 10
  @default_pool_name __MODULE__

  # Client API

  @doc """
  Start the pool supervisor.
  """
  def start_link(opts) do
    pool_name = Keyword.get(opts, :name, @default_pool_name)
    Supervisor.start_link(__MODULE__, opts, name: :"#{pool_name}.Supervisor")
  end

  @doc """
  Publish a message to a topic using a pooled connection.

  Same API as MaculaSdk.Wamp.Client.publish/5 but uses pooled connection.
  """
  def publish(topic, args \\ [], kwargs \\ %{}, options \\ %{}, pool_name \\ @default_pool_name) do
    execute_with_pool(pool_name, fn worker ->
      MaculaSdk.Wamp.Client.publish(worker, topic, args, kwargs, options)
    end)
  end

  @doc """
  Subscribe to a topic using a pooled connection.

  **Important**: The handler function will be called in the context of the
  pool worker process. For long-running handlers, consider sending a message
  to a dedicated process instead.

  Same API as MaculaSdk.Wamp.Client.subscribe/4 but uses pooled connection.
  """
  def subscribe(topic, handler_fun, options \\ %{}, pool_name \\ @default_pool_name) do
    execute_with_pool(pool_name, fn worker ->
      MaculaSdk.Wamp.Client.subscribe(worker, topic, handler_fun, options)
    end)
  end

  @doc """
  Call a remote procedure using a pooled connection.

  Same API as MaculaSdk.Wamp.Client.call/5 but uses pooled connection.
  """
  def call(procedure, args \\ [], kwargs \\ %{}, options \\ %{}, pool_name \\ @default_pool_name) do
    execute_with_pool(pool_name, fn worker ->
      MaculaSdk.Wamp.Client.call(worker, procedure, args, kwargs, options)
    end)
  end

  @doc """
  Register a procedure for RPC using a pooled connection.

  **Important**: The handler function will be called in the context of the
  pool worker process. For long-running handlers, consider sending a message
  to a dedicated process instead.

  Same API as MaculaSdk.Wamp.Client.register/4 but uses pooled connection.
  """
  def register(procedure, handler_fun, options \\ %{}, pool_name \\ @default_pool_name) do
    execute_with_pool(pool_name, fn worker ->
      MaculaSdk.Wamp.Client.register(worker, procedure, handler_fun, options)
    end)
  end

  @doc """
  Wait for pool workers to be ready (connected to WAMP router).

  Polls workers until at least `min_ready` workers are connected.
  Returns `:ok` when ready, or `{:error, :timeout}` after timeout.

  ## Options
  - `:min_ready` - Minimum number of connected workers (default: 1)
  - `:timeout` - Maximum wait time in ms (default: 10_000)
  - `:poll_interval` - Check interval in ms (default: 100)

  ## Example
      # Wait for at least 5 workers to be ready
      MaculaSdk.Wamp.Pool.wait_for_ready(MyPool, min_ready: 5, timeout: 5_000)
  """
  def wait_for_ready(pool_name \\ @default_pool_name, opts \\ []) do
    min_ready = Keyword.get(opts, :min_ready, 1)
    timeout = Keyword.get(opts, :timeout, 10_000)
    poll_interval = Keyword.get(opts, :poll_interval, 100)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for_ready(pool_name, min_ready, poll_interval, deadline)
  end

  @doc """
  Get pool statistics.

  Returns information about pool usage:
  - `:workers` - Number of worker processes
  - `:available` - Number of available workers
  - `:overflow` - Number of overflow workers
  - `:monitors` - Number of monitored checkouts
  """
  def stats(pool_name \\ @default_pool_name) do
    :poolboy.status(pool_name)
  end

  # Supervisor Callbacks

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    realm = Keyword.fetch!(opts, :realm)
    pool_size = Keyword.get(opts, :pool_size, @default_pool_size)
    max_overflow = Keyword.get(opts, :max_overflow, @default_max_overflow)
    pool_name = Keyword.get(opts, :name, @default_pool_name)
    api_key = Keyword.get(opts, :api_key)
    username = Keyword.get(opts, :username)
    password = Keyword.get(opts, :password)

    # Build worker args for WAMP client
    worker_args = [
      url: url,
      realm: realm,
      api_key: api_key,
      username: username,
      password: password
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    # Poolboy configuration
    poolboy_config = [
      name: {:local, pool_name},
      worker_module: MaculaSdk.Wamp.Client,
      size: pool_size,
      max_overflow: max_overflow
    ]

    children = [
      :poolboy.child_spec(pool_name, poolboy_config, worker_args)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private Functions

  defp execute_with_pool(pool_name, fun) do
    worker = :poolboy.checkout(pool_name)

    try do
      fun.(worker)
    after
      :poolboy.checkin(pool_name, worker)
    end
  catch
    :exit, {:noproc, _} ->
      Logger.error("#{__MODULE__}: Pool #{pool_name} not available")
      {:error, :pool_not_available}

    :exit, reason ->
      Logger.error("#{__MODULE__}: Worker crash: #{inspect(reason)}")
      {:error, :worker_crash}
  end

  defp do_wait_for_ready(pool_name, min_ready, poll_interval, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      Logger.error("#{__MODULE__}: Timeout waiting for #{min_ready} workers to be ready")
      {:error, :timeout}
    else
      ready_count = count_ready_workers(pool_name)

      if ready_count >= min_ready do
        Logger.info("#{__MODULE__}: Pool ready with #{ready_count} connected workers")
        :ok
      else
        Logger.debug("#{__MODULE__}: #{ready_count}/#{min_ready} workers ready, waiting...")
        Process.sleep(poll_interval)
        do_wait_for_ready(pool_name, min_ready, poll_interval, deadline)
      end
    end
  end

  defp count_ready_workers(pool_name) do
    # Get pool status from poolboy
    # :poolboy.status/1 returns {state_name, pool_size, overflow_size, num_monitors}
    # But we need to actually check each worker's connection status
    # So we'll checkout all available workers and check their status

    status = :poolboy.status(pool_name)
    pool_size = elem(status, 1)  # Second element is pool size

    # Check up to pool_size workers
    check_workers(pool_name, pool_size, 0)
  catch
    # If there's any error checking workers, return 0
    _kind, _reason -> 0
  end

  defp check_workers(_pool_name, 0, ready_count), do: ready_count

  defp check_workers(pool_name, remaining, ready_count) do
    case checkout_and_check(pool_name) do
      {:ok, is_ready} ->
        new_count = if is_ready, do: ready_count + 1, else: ready_count
        check_workers(pool_name, remaining - 1, new_count)

      {:error, _} ->
        # Can't checkout more workers, return current count
        ready_count
    end
  end

  defp checkout_and_check(pool_name) do
    try do
      worker = :poolboy.checkout(pool_name, false)  # non-blocking checkout

      try do
        # Check worker status
        status = MaculaSdk.Wamp.Client.status(worker)
        is_ready = status[:status] == :connected
        {:ok, is_ready}
      after
        :poolboy.checkin(pool_name, worker)
      end
    catch
      :exit, {:noproc, _} -> {:error, :pool_unavailable}
      :exit, _ -> {:error, :no_workers_available}
    end
  end
end
