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
    home_count = get_env("HOME_COUNT", "25") |> String.to_integer()
    home_id_offset = get_env("HOME_ID_OFFSET", "0") |> String.to_integer()
    bondy_url = get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = get_env("BONDY_REALM", "be.cortexiq.energy")

    Logger.info("Starting #{home_count} home bots (offset: #{home_id_offset})")

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
        Task.start(fn -> start_home_bots_staggered(home_count, home_id_offset, bondy_url, realm) end)
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_home_bots_staggered(count, offset, bondy_url, realm) do
    # Stagger startup to avoid overwhelming Bondy with connections
    # For 1000 homes with 25ms delay = 25 seconds total startup time
    # More gradual for better visual effect on dashboard
    delay_ms = 25

    Logger.info("Starting #{count} home bots with #{delay_ms}ms stagger...")

    Enum.each(offset..(offset + count - 1), fn i ->
      home_id = "home_#{String.pad_leading("#{i + 1}", 4, "0")}"  # 4 digits for 1000 homes

      spec = {CortexIqHomes.HomeBot, [
        home_id: home_id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          if rem(i + 1, 100) == 0 do
            Logger.info("Started #{i + 1} home bots...")
          end

        {:error, reason} ->
          Logger.error("Failed to start HomeBot #{home_id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("Finished starting all #{count} home bots!")
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
