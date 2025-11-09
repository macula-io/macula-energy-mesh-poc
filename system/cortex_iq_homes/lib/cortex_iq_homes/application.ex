defmodule CortexIqHomes.Application do
  @moduledoc """
  Application supervisor for CortexIQ Homes.

  Manages home bot processes that simulate homes with solar, battery, and contract optimization.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("========== CortexIqHomes.Application.start called ==========")

    # Get configuration from environment variables or config files
    # Priority: ENV > config > defaults
    homes_sources = get_env("HOMES_SOURCES", "flanders_test_homes.json")
    macula_url = get_env("MACULA_URL", get_config(:macula_url, "https://localhost:9443"))
    realm = get_env("MACULA_REALM", get_config(:macula_realm, "be.cortexiq.energy"))

    Logger.info("Configuration loaded: homes_sources=#{homes_sources}, macula_url=#{macula_url}, realm=#{realm}")

    # Load homes from JSON configuration (supports comma-separated list)
    Logger.info("About to load homes from #{homes_sources}...")

    homes =
      try do
        loaded = CortexIqHomes.ConfigLoader.load_homes_from_sources(homes_sources)
        Logger.info("Successfully loaded #{length(loaded)} homes!")
        loaded
      rescue
        error ->
          Logger.error("FATAL: Failed to load homes: #{inspect(error)}")
          Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
          raise error
      end

    Logger.info("Starting #{length(homes)} home bots from #{homes_sources}")

    Logger.info("🔧 Building supervision tree with 5 children...")
    Logger.info("  1. Registry")
    Logger.info("  2. Phoenix.PubSub")
    Logger.info("  3. SubscribeSimulationTimeAdvanced.System")
    Logger.info("  4. SubscribeSimulationReset.Subscriber")
    Logger.info("  5. DynamicSupervisor (BotSupervisor)")

    children = [
      # Registry for home bots
      {Registry, keys: :unique, name: CortexIqHomes.Registry},

      # PubSub for internal event broadcasting
      {Phoenix.PubSub, name: CortexIqHomes.PubSub},

      # Simulation time subscription (broadcasts to all homes via PubSub)
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.System, [
        macula_url: macula_url,
        realm: realm
      ]},

      # Singleton subscriber for simulation reset events
      {CortexIqHomes.SubscribeSimulationReset.Subscriber, [
        macula_url: macula_url,
        realm: realm
      ]},

      # Dynamic supervisor for home bots
      {DynamicSupervisor, name: CortexIqHomes.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: CortexIqHomes.Supervisor]

    Logger.info("🚀 Starting Supervisor with #{length(children)} children...")

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("✅ Supervisor started successfully with PID: #{inspect(pid)}")
        Logger.info("📊 Verifying children are alive...")

        # Verify critical children started
        children_status = [
          {"Registry", Process.whereis(CortexIqHomes.Registry)},
          {"PubSub", Process.whereis(CortexIqHomes.PubSub)},
          {"SubscribeSimulationTimeAdvanced.System", Process.whereis(CortexIqHomes.SubscribeSimulationTimeAdvanced.System)},
          {"BotSupervisor", Process.whereis(CortexIqHomes.BotSupervisor)}
        ]

        Enum.each(children_status, fn {name, pid} ->
          if pid do
            Logger.info("  ✓ #{name}: #{inspect(pid)}")
          else
            Logger.error("  ❌ #{name}: NOT FOUND")
          end
        end)

        # Start home bots asynchronously to avoid blocking
        # Use Task to start them in the background with staggered delays
        Logger.info("Starting home bots...")
        Task.start(fn -> start_home_bots_staggered(homes, macula_url, realm) end)
        {:ok, pid}

      error ->
        Logger.error("❌ Failed to start Supervisor: #{inspect(error)}")
        error
    end
  end

  defp start_home_bots_staggered(homes, macula_url, realm) do
    # Batch-based staggering to avoid overwhelming Macula
    # Strategy: Start homes in small batches with long pauses between batches
    # This prevents connection storms and gives Macula time to process HELLO handshakes

    batch_size = 25              # Small batch size to limit concurrent connections
    base_delay_ms = 200          # Conservative delay within batch
    jitter_ms = 100              # Random variation to avoid synchronized waves
    batch_pause_ms = 8000        # Long pause between batches (8 seconds)

    total_batches = div(length(homes) + batch_size - 1, batch_size)
    total_time_estimate = (total_batches * batch_pause_ms + length(homes) * (base_delay_ms + jitter_ms / 2)) / 1000

    Logger.info("Starting #{length(homes)} homes in #{total_batches} batches of #{batch_size}")
    Logger.info("Strategy: #{base_delay_ms}ms + 0-#{jitter_ms}ms per home, #{batch_pause_ms}ms between batches")
    Logger.info("Estimated total time: #{Float.round(total_time_estimate, 1)}s")

    homes
    |> Enum.chunk_every(batch_size)
    |> Enum.with_index()
    |> Enum.each(fn {batch, batch_num} ->
      Logger.info("Starting batch #{batch_num + 1}/#{total_batches} (#{length(batch)} homes)...")

      # Start homes in this batch with individual delays
      Enum.each(batch, fn home ->
        spec = {CortexIqHomes.HomeSupervisor, [
          home: home,
          home_id: home.id,
          macula_url: macula_url,
          realm: realm
        ]}

        case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
          {:ok, _pid} ->
            :ok

          {:error, reason} ->
            Logger.error("Failed to start HomeSupervisor for #{home.id}: #{inspect(reason)}")
        end

        # Staggered delay with random jitter
        delay = base_delay_ms + :rand.uniform(jitter_ms)
        Process.sleep(delay)
      end)

      # Long pause between batches (except after last batch)
      if batch_num < total_batches - 1 do
        Logger.info("Batch #{batch_num + 1} complete. Waiting #{batch_pause_ms}ms before next batch...")
        Process.sleep(batch_pause_ms)
      end
    end)

    Logger.info("Finished starting all #{length(homes)} home systems!")
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end

  defp get_config(key, default) do
    Application.get_env(:cortex_iq_homes, key, default)
  end
end
