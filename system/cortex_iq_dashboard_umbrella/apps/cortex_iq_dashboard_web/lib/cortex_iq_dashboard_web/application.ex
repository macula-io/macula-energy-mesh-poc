defmodule CortexIqDashboardWeb.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CortexIqDashboardWeb.Telemetry,
      # CortexIqDashboard.PubSub is started by mesh_hub application
      # Start a worker by calling: CortexIqDashboardWeb.Worker.start_link(arg)
      # {CortexIqDashboardWeb.Worker, arg},
      # Start to serve requests, typically the last entry
      CortexIqDashboardWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqDashboardWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CortexIqDashboardWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
