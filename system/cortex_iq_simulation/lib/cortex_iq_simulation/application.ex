defmodule CortexIqSimulation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Simulation clock - broadcasts time to all WAMP subscribers
      CortexIqSimulation.SimulationClock
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqSimulation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
