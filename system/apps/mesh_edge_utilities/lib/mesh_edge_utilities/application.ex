defmodule MeshEdgeUtilities.Application do
  @moduledoc """
  Application supervisor for mesh_edge_utilities.

  Manages utility provider bot processes.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    provider_count = get_env("PROVIDER_COUNT", "5") |> String.to_integer()
    bondy_url = get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = get_env("BONDY_REALM", "com.energy.mesh")

    Logger.info("Starting #{provider_count} provider bots")

    children = [
      # Registry for provider bots
      {Registry, keys: :unique, name: MeshEdgeUtilities.Registry},

      # Dynamic supervisor for provider bots
      {DynamicSupervisor, name: MeshEdgeUtilities.BotSupervisor, strategy: :one_for_one}
    ]

    opts = [strategy: :one_for_one, name: MeshEdgeUtilities.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        # Start provider bots
        start_provider_bots(provider_count, bondy_url, realm)
        {:ok, pid}

      error ->
        error
    end
  end

  defp start_provider_bots(count, bondy_url, realm) do
    Enum.each(1..count, fn i ->
      provider_id = "provider_#{i}"

      spec = {MeshEdgeUtilities.ProviderBot, [
        provider_id: provider_id,
        bondy_url: bondy_url,
        realm: realm
      ]}

      case DynamicSupervisor.start_child(MeshEdgeUtilities.BotSupervisor, spec) do
        {:ok, _pid} ->
          Logger.info("Started ProviderBot: #{provider_id}")

        {:error, reason} ->
          Logger.error("Failed to start ProviderBot #{provider_id}: #{inspect(reason)}")
      end
    end)
  end

  defp get_env(key, default) do
    System.get_env(key, default)
  end
end
