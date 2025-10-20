defmodule MeshEdgeHomes.Application do
  @moduledoc """
  Application supervisor for mesh_edge_homes.

  Manages home bot processes.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    home_count = get_env("HOME_COUNT", "25") |> String.to_integer()
    home_id_offset = get_env("HOME_ID_OFFSET", "0") |> String.to_integer()
    bondy_url = get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = get_env("BONDY_REALM", "com.energy.mesh")

    Logger.info("Starting #{home_count} home bots (offset: #{home_id_offset})")

    children = [
      # Registry for home bots
      {Registry, keys: :unique, name: MeshEdgeHomes.Registry},

      # Dynamic supervisor for home bots
      {DynamicSupervisor, name: MeshEdgeHomes.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: MeshEdgeHomes.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Start home bots
        start_home_bots(home_count, home_id_offset, bondy_url, realm)
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_home_bots(count, offset, bondy_url, realm) do
    Enum.each(offset..(offset + count - 1), fn i ->
      home_id = "home_#{String.pad_leading("#{i + 1}", 3, "0")}"

      spec = {MeshEdgeHomes.HomeBot, [
        home_id: home_id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(MeshEdgeHomes.BotSupervisor, spec) do
        {:ok, _pid} ->
          Logger.info("Started HomeBot: #{home_id}")

        {:error, reason} ->
          Logger.error("Failed to start HomeBot #{home_id}: #{inspect(reason)}")
      end
    end)
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
