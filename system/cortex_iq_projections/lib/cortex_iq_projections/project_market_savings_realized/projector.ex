defmodule CortexIqProjections.ProjectMarketSavingsRealized.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.market.savings_realized events.

  Projects market.savings_realized events (CortexIQ commission)
  """
  use GenServer
  require Logger
  import Ecto.Query
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
  alias CortexIqDashboardSchemas.TimeSeries.{EnergyEvent, EnergyTrade, ContractEvent}

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def project_event(event_data) do
    GenServer.cast(__MODULE__, {:project, event_data})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ProjectMarketSavingsRealized.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_market_savings_realized(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_market_savings_realized(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    gross_savings = kwargs["gross_savings"] || 0.0
    commission = kwargs["cortexiq_commission"] || 0.0
    net_savings = kwargs["net_savings_to_customer"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update home state with cumulative savings
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          cortexiq_total_commission: commission,
          cortexiq_total_savings: gross_savings,
          cortexiq_net_savings: net_savings,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # Update system stats
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(
      inc: [
        cortexiq_total_commission: commission,
        cortexiq_total_savings: gross_savings,
        cortexiq_net_savings: net_savings
      ],
      set: [updated_at: DateTime.utc_now()]
    )
  rescue
    error ->
      Logger.error("VerticalSliceGenerator: Error: #{inspect(error)}")
  end


  # Helper Functions

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
