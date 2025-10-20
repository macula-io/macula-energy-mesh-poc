defmodule MeshHub.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    realm_uri = System.get_env("BONDY_REALM", "com.energy.mesh")
    bondy_admin_url = System.get_env("BONDY_ADMIN_URL", "http://localhost:18081")
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")

    children = [
      MeshHub.Repo,
      {DNSCluster, query: Application.get_env(:mesh_hub, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MeshHub.PubSub},
      {MeshHub.System, [
        realm_uri: realm_uri,
        bondy_admin_url: bondy_admin_url,
        bondy_url: bondy_url
      ]},
    ]

    opts = [strategy: :one_for_one, name: MeshHub.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    Logger.warning("=" <> String.duplicate("=", 60))
    Logger.warning("MeshHub.Application.stop/1 called")
    Logger.warning("  Supervisor tree will now shutdown (children terminate in LIFO order)")
    Logger.warning("=" <> String.duplicate("=", 60))
    :ok
  end
end





