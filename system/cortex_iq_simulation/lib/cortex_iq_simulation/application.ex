defmodule CortexIqSimulation.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    children = [
      # Simulation clock - broadcasts time to all WAMP subscribers
      CortexIqSimulation.SimulationClock,

      # RPC Systems - each handles one simulation control procedure
      {CortexIqSimulation.ResetSimulation.System,
       bondy_url: bondy_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.PauseSimulation.System,
       bondy_url: bondy_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.ResumeSimulation.System,
       bondy_url: bondy_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock},

      {CortexIqSimulation.SetSimulationSpeed.System,
       bondy_url: bondy_url,
       realm: realm,
       simulation_clock: CortexIqSimulation.SimulationClock}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CortexIqSimulation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
