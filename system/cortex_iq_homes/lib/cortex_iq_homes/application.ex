defmodule CortexIqHomes.Application do
  @moduledoc """
  Application supervisor for CortexIQ Homes.

  Manages home bot processes that simulate homes with solar, battery, and contract optimization.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    homes_source = get_env("HOMES_SOURCE", "flanders_test_homes.json")
    bondy_url = get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = get_env("BONDY_REALM", "be.cortexiq.energy")

    # Load homes from JSON configuration
    homes = CortexIqHomes.ConfigLoader.load_homes(homes_source)

    Logger.info("Starting #{length(homes)} home bots from #{homes_source}")

    children = [
      # Registry for home bots
      {Registry, keys: :unique, name: CortexIqHomes.Registry},

      # Dynamic supervisor for home bots
      {DynamicSupervisor, name: CortexIqHomes.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: CortexIqHomes.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Start home bots asynchronously to avoid blocking
        # Use Task to start them in the background with staggered delays
        Task.start(fn -> start_home_bots_staggered(homes, bondy_url, realm) end)
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_home_bots_staggered(homes, bondy_url, realm) do
    # Stagger startup to avoid overwhelming Bondy with connections
    # For 50 homes with 25ms delay = 1.25 seconds total startup time
    delay_ms = 25

    Logger.info("Starting #{length(homes)} home bots with #{delay_ms}ms stagger...")

    Enum.each(homes, fn home ->
      spec = {CortexIqHomes.HomeBot, [
        home: home,
        home_id: home.id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to start HomeBot #{home.id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("Finished starting all #{length(homes)} home bots!")
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
