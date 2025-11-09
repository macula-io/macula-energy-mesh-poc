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

    # Get Macula configuration from environment
    macula_url = System.get_env("MACULA_URL", "https://localhost:9443")
    realm_uri = System.get_env("MACULA_REALM", "be.cortexiq.energy")

    children = [
      # Database repository (write side of CQRS)
      CortexIqProjections.Repo,

      # Shared Macula client (HTTP/3 QUIC multiplexes all projection subscriptions)
      # All projection systems share this client via QUIC stream multiplexing
      %{
        id: :macula_client,
        start: {MaculaSdk.Client, :start_link, [
          [
            name: CortexIqProjections.MaculaClient,
            url: macula_url,
            realm: realm_uri
          ]
        ]}
      },

      # VERTICAL SLICE ARCHITECTURE
      # Each event type has its own dedicated system:
      # - Subscriber (subscribes to specific topic via shared client)
      # - Projector (Broadway for high-volume, GenServer for low-volume)

      # CRITICAL SYSTEMS ONLY (to reduce connection load while pool refactoring is in progress)
      # TODO: Gradually re-enable other systems after migrating them to use shared client

      # Provider metrics calculation system
      # Tracks provider financial metrics, market share, activity, and competitive positioning
      # Stores in provider_states table and publishes to be.cortexiq.provider.metrics_calculated
      {CortexIqProjections.CalculateProviderMetrics.System, [client: CortexIqProjections.MaculaClient]},

      # System totals calculation (ENABLED for dashboard data)
      # This system subscribes to home events and publishes aggregated totals
      # to be.cortexiq.projections.totals_calculated topic
      {CortexIqProjections.CalculateSystemTotals.System, [client: CortexIqProjections.MaculaClient]}

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
