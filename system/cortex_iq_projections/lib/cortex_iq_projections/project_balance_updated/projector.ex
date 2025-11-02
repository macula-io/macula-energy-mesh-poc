defmodule CortexIqProjections.ProjectBalanceUpdated.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.balance.updated events.

  Projects balance.updated events (cumulative energy balance)
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
    Logger.info("ProjectBalanceUpdated.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_balance_updated(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_balance_updated(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    energy_bought_kwh = kwargs["energy_bought_kwh"] || 0.0
    energy_sold_kwh = kwargs["energy_sold_kwh"] || 0.0
    net_balance_kwh = kwargs["net_balance_kwh"] || 0.0
    cost_paid = kwargs["cost_paid"] || 0.0
    revenue_received = kwargs["revenue_received"] || 0.0
    net_cost = kwargs["net_cost"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          energy_bought_kwh: energy_bought_kwh,
          energy_sold_kwh: energy_sold_kwh,
          net_balance_kwh: net_balance_kwh,
          cost_paid: cost_paid,
          revenue_received: revenue_received,
          net_cost: net_cost,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
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
