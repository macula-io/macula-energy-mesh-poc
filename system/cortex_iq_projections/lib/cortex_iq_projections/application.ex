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

      # EventProjector: WAMP subscription bridge
      CortexIqProjections.EventProjector,

      # Broadway pipeline for event processing with back-pressure
      # EventPipeline will fetch WAMP client from EventProjector when it needs it
      CortexIqProjections.EventPipeline
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
