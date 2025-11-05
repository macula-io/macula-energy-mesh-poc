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

    # Get WAMP configuration from environment
    bondy_url = System.get_env("BONDY_URL", "ws://localhost:18080/ws")
    realm_uri = System.get_env("BONDY_REALM", "be.cortexiq.energy")

    children = [
      # Database repository (write side of CQRS)
      CortexIqProjections.Repo,

      # Shared WAMP connection pool (replaces 22 individual connections)
      # All projection systems share this pool to avoid overwhelming Bondy
      {MaculaSdk.Wamp.Pool, [
        url: bondy_url,
        realm: realm_uri,
        pool_size: 5,
        max_overflow: 2,
        name: CortexIqProjections.WampPool
      ]},

      # VERTICAL SLICE ARCHITECTURE
      # Each event type has its own dedicated system:
      # - Subscriber (subscribes to specific topic via shared pool)
      # - Projector (Broadway for high-volume, GenServer for low-volume)

      # CRITICAL SYSTEMS ONLY (to reduce connection load while pool refactoring is in progress)
      # TODO: Gradually re-enable other systems after refactoring them to use the pool

      # Provider metrics calculation system (REFACTORED to use pool)
      # Tracks provider financial metrics, market share, activity, and competitive positioning
      # Stores in provider_states table and publishes to be.cortexiq.provider.metrics_calculated
      {CortexIqProjections.CalculateProviderMetrics.System, []},

      # System totals calculation (ENABLED for dashboard data)
      # This system subscribes to home events and publishes aggregated totals
      # to be.cortexiq.projections.totals_calculated topic
      {CortexIqProjections.CalculateSystemTotals.System, []}

      # TEMPORARILY DISABLED (need pool refactoring):
      # {CortexIqProjections.RegisterHome.System, []},
      # {CortexIqProjections.ProjectHomeMeasured.System, []},
      # {CortexIqProjections.ProjectSimulationTimeAdvanced.System, []},
      # {CortexIqProjections.ProjectSimulationReset.System, []},
      # {CortexIqProjections.ProjectHomeInitialized.System, []},
      # {CortexIqProjections.ProjectHomeConnected.System, []},
      # {CortexIqProjections.ProjectHomeDisconnected.System, []},
      # {CortexIqProjections.ProjectHomeTraded.System, []},
      # {CortexIqProjections.ProjectBalanceUpdated.System, []},
      # {CortexIqProjections.ProjectMarketContractProposed.System, []},
      # {CortexIqProjections.ProjectMarketContractConfirmed.System, []},
      # {CortexIqProjections.ProjectMarketContractRejected.System, []},
      # {CortexIqProjections.ProjectMarketContractSwitched.System, []},
      # {CortexIqProjections.ProjectMarketContractExpired.System, []},
      # {CortexIqProjections.ProjectMarketTradeExecuted.System, []},
      # {CortexIqProjections.ProjectMarketSavingsRealized.System, []},
      # {CortexIqProjections.ProjectMarketSpotPriceUpdated.System, []},
      # {CortexIqProjections.ProjectArbitrageProfitRealized.System, []},
      # {CortexIqProjections.CalculateCityTotals.System, []},
      # {CortexIqProjections.CalculateMetrics.System, []}
    ]

    opts = [strategy: :one_for_one, name: CortexIqProjections.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
