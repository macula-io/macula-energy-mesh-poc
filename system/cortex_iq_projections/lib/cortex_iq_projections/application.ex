defmodule CortexIqProjections.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Run migrations on startup (production pattern)
    if Application.get_env(:cortex_iq_projections, :run_migrations_on_start, true) do
      CortexIqProjections.Release.migrate()
    end

    children = [
      # Database repository (write side of CQRS)
      CortexIqProjections.Repo,

      # VERTICAL SLICE ARCHITECTURE
      # Each event type has its own dedicated system:
      # - WAMP Client (unique per event type)
      # - Subscriber (subscribes to specific topic)
      # - Projector (Broadway for high-volume, GenServer for low-volume)

      # RPC procedure: register_home (write operation)
      {CortexIqProjections.RegisterHome.System, []},

      # High-volume event (Broadway with batching)
      {CortexIqProjections.ProjectHomeMeasured.System, []},

      # Simulation control events
      {CortexIqProjections.ProjectSimulationTimeAdvanced.System, []},
      {CortexIqProjections.ProjectSimulationReset.System, []},

      # Home lifecycle events
      {CortexIqProjections.ProjectHomeInitialized.System, []},
      {CortexIqProjections.ProjectHomeConnected.System, []},
      {CortexIqProjections.ProjectHomeDisconnected.System, []},
      {CortexIqProjections.ProjectHomeTraded.System, []},

      # Balance tracking events
      {CortexIqProjections.ProjectBalanceUpdated.System, []},

      # Market contract events
      {CortexIqProjections.ProjectMarketContractProposed.System, []},
      {CortexIqProjections.ProjectMarketContractConfirmed.System, []},
      {CortexIqProjections.ProjectMarketContractRejected.System, []},
      {CortexIqProjections.ProjectMarketContractSwitched.System, []},
      {CortexIqProjections.ProjectMarketContractExpired.System, []},

      # Market trading events
      {CortexIqProjections.ProjectMarketTradeExecuted.System, []},
      {CortexIqProjections.ProjectMarketSavingsRealized.System, []},
      {CortexIqProjections.ProjectMarketSpotPriceUpdated.System, []},

      # Arbitrage events
      {CortexIqProjections.ProjectArbitrageProfitRealized.System, []},

      # System totals calculation (aggregating projection)
      {CortexIqProjections.CalculateSystemTotals.System, []}
    ]

    opts = [strategy: :one_for_one, name: CortexIqProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
