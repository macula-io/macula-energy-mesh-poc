defmodule Mesh.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Mesh.Repo,
      {DNSCluster, query: Application.get_env(:mesh, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mesh.PubSub}
      # Start a worker by calling: Mesh.Worker.start_link(arg)
      # {Mesh.Worker, arg}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Mesh.Supervisor)
  end
end
