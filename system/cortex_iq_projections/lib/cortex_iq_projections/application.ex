defmodule CortexIqProjections.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database repository (write side of CQRS)
      CortexIqProjections.Repo,

      # WAMP event subscriber that projects events into database
      CortexIqProjections.EventProjector
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
