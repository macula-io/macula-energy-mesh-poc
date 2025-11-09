defmodule CortexIqSimulation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration
    # CLIENT MODE: Connect to standalone city gateway
    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")
    realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")

    children = [
      # 1. Simulation clock - broadcasts time to all subscribers
      CortexIqSimulation.SimulationClock,

      # 2. RPC Systems - connect to city gateway
      {CortexIqSimulation.ResetSimulation.System,
       macula_url: macula_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.PauseSimulation.System,
       macula_url: macula_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.ResumeSimulation.System,
       macula_url: macula_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.SetSimulationSpeed.System,
       macula_url: macula_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqSimulation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
