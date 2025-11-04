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
    bondy_url = get_env("BONDY_URL", get_config(:bondy_url, "ws://localhost:18080/ws"))
    realm = get_env("BONDY_REALM", get_config(:bondy_realm, "be.cortexiq.energy"))

    Logger.info("Configuration loaded: homes_sources=#{homes_sources}, bondy_url=#{bondy_url}, realm=#{realm}")

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

    children = [
      # Registry for home bots
      {Registry, keys: :unique, name: CortexIqHomes.Registry},

      # PubSub for internal event broadcasting
      {Phoenix.PubSub, name: CortexIqHomes.PubSub},

      # Shared WAMP connection pool (20 connections for all homes)
      {MaculaSdk.Wamp.Pool, [
        url: bondy_url,
        realm: realm,
        pool_size: 20,
        max_overflow: 10,
        name: CortexIqHomes.WampPool
      ]},

      # Simulation time subscription (broadcasts to all homes via PubSub)
      {CortexIqHomes.SubscribeSimulationTimeAdvanced.System, [
        bondy_url: bondy_url,
        realm_uri: realm
      ]},

      # Singleton subscriber for simulation reset events
      {CortexIqHomes.SubscribeSimulationReset.Subscriber, [pool_name: CortexIqHomes.WampPool]},

      # Dynamic supervisor for home bots
      {DynamicSupervisor, name: CortexIqHomes.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: CortexIqHomes.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Wait for WAMP pool to be ready before starting homes
        # This prevents :not_connected errors during subscriber initialization
        Logger.info("Waiting for WAMP pool to be ready...")

        case MaculaSdk.Wamp.Pool.wait_for_ready(CortexIqHomes.WampPool, min_ready: 5, timeout: 10_000) do
          :ok ->
            Logger.info("✓ WAMP pool ready, starting home bots...")
            # Start home bots asynchronously to avoid blocking
            # Use Task to start them in the background with staggered delays
            Task.start(fn -> start_home_bots_staggered(homes, bondy_url, realm) end)
            {:ok, pid}

          {:error, :timeout} ->
            Logger.error("Timeout waiting for WAMP pool to be ready. Starting homes anyway (they will retry)...")
            Task.start(fn -> start_home_bots_staggered(homes, bondy_url, realm) end)
            {:ok, pid}
        end

      error ->
        error
    end
  end

  defp start_home_bots_staggered(homes, bondy_url, realm) do
    # Stagger startup to avoid overwhelming Bondy with connections
    # For 50 homes with 25ms delay = 1.25 seconds total startup time
    delay_ms = 25

    Logger.info("Starting #{length(homes)} home systems (vertical slices) with #{delay_ms}ms stagger...")

    Enum.each(homes, fn home ->
      spec = {CortexIqHomes.HomeSupervisor, [
        home: home,
        home_id: home.id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to start HomeSupervisor for #{home.id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("Finished starting all #{length(homes)} home systems (#{length(homes) * 16} processes total)!")
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end

  defp get_config(key, default) do
    Application.get_env(:cortex_iq_homes, key, default)
  end
end
