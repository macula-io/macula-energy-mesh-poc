defmodule MeshHubWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MeshHubWeb.Telemetry,
      # MeshHub.PubSub is started by mesh_hub application
      # Start a worker by calling: MeshHubWeb.Worker.start_link(arg)
      # {MeshHubWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      MeshHubWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: MeshHubWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MeshHubWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
