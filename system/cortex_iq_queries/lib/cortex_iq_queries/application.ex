defmodule CortexIqQueries.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")
    realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")

    children = [
      # Database connection pool
      CortexIqQueries.Repo,
      # RPC server (registers query procedures via HTTP/3)
      {CortexIqQueries.RpcServer, [macula_url: macula_url, realm: realm]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqQueries.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
