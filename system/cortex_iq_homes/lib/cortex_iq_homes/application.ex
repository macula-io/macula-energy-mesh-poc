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
    num_homes = get_env("NUM_HOMES", "50") |> String.to_integer()
    home_id_filter = get_env("HOME_ID_FILTER", "all")  # "all", "odd", "even"
    bondy_url = get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = get_env("BONDY_REALM", "be.cortexiq.energy")

    home_ids = filter_home_ids(1..num_homes, home_id_filter)

    Logger.info("Starting #{length(home_ids)} home bots (filter: #{home_id_filter}, total: #{num_homes})")

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
        Task.start(fn -> start_home_bots_staggered(home_ids, bondy_url, realm) end)
        {:ok, pid}

      error ->
        error
    end
  end

  defp filter_home_ids(range, filter) do
    case filter do
      "odd" ->
        Enum.filter(range, fn id -> rem(id, 2) == 1 end)

      "even" ->
        Enum.filter(range, fn id -> rem(id, 2) == 0 end)

      _ ->
        Enum.to_list(range)
    end
  end

  defp start_home_bots_staggered(home_ids, bondy_url, realm) do
    # Stagger startup to avoid overwhelming Bondy with connections
    # For 50 homes with 25ms delay = 1.25 seconds total startup time
    delay_ms = 25

    Logger.info("Starting #{length(home_ids)} home bots with #{delay_ms}ms stagger...")

    Enum.each(home_ids, fn home_num ->
      home_id = "home_#{String.pad_leading("#{home_num}", 4, "0")}"  # 4 digits for consistency

      spec = {CortexIqHomes.HomeBot, [
        home_id: home_id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(CortexIqHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          :ok

        {:error, reason} ->
          Logger.error("Failed to start HomeBot #{home_id}: #{inspect(reason)}")
      end

      # Small delay to stagger WAMP connections
      Process.sleep(delay_ms)
    end)

    Logger.info("Finished starting all #{length(home_ids)} home bots!")
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
