defmodule CortexIqQueries.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    children = [
      # Database connection pool
      CortexIqQueries.Repo,
      # WAMP RPC server (registers query procedures)
      {CortexIqQueries.RpcServer, [bondy_url: bondy_url, realm: realm]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqQueries.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
