defmodule CortexIqProjections.ProjectHomeTraded.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.home.traded events.

  Projects home.traded events (energy buy/sell transactions)
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
    Logger.info("ProjectHomeTraded.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_home_traded(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_home_traded(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    provider_id = kwargs["provider_id"]
    contract_id = kwargs["contract_id"]
    type = String.to_atom(kwargs["type"] || "buy")
    kwh = kwargs["kwh"] || 0.0
    price_per_kwh = kwargs["price_per_kwh"] || 0.0
    total = kwargs["total"] || 0.0
    is_day = kwargs["is_day"] || true
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Insert into energy_trades time-series table
    {import_kwh, export_kwh, import_cost, export_revenue} =
      case type do
        :buy -> {kwh, 0.0, total, 0.0}
        :sell -> {0.0, kwh, 0.0, total}
      end

    Repo.insert!(
      %EnergyTrade{
        home_id: home_id,
        provider_id: provider_id,
        contract_id: contract_id,
        simulation_time: simulation_time,
        simulation_hour: simulation_time.hour,
        grid_import_kwh: import_kwh,
        grid_export_kwh: export_kwh,
        import_price_per_kwh: if(type == :buy, do: price_per_kwh, else: nil),
        export_price_per_kwh: if(type == :sell, do: price_per_kwh, else: nil),
        is_day: is_day,
        import_cost: import_cost,
        export_revenue: export_revenue,
        net_cost: import_cost - export_revenue,
        recorded_at: DateTime.utc_now()
      },
      on_conflict: :nothing,
      conflict_target: [:home_id, :simulation_time]
    )

    # Accumulate revenue and cost in provider_states
    # From provider perspective:
    #  - When home buys (imports), provider earns revenue (import_cost)
    #  - When home sells (exports), provider pays cost (export_revenue)
    if provider_id do
      # Get current provider state
      case Repo.get(ProviderState, provider_id) do
        nil ->
          # Provider doesn't exist yet, skip update
          # (It will be created when contract_proposed event arrives)
          :ok

        provider ->
          # Accumulate financials
          new_revenue = (provider.total_revenue || 0.0) + import_cost
          new_cost = (provider.total_cost || 0.0) + export_revenue
          new_profit = new_revenue - new_cost

          # Update provider state
          Repo.update!(
            ProviderState.changeset(provider, %{
              total_revenue: new_revenue,
              total_cost: new_cost,
              net_profit: new_profit,
              last_event_at: simulation_time,
              updated_at: DateTime.utc_now()
            })
          )
      end
    end
  rescue
    error ->
      Logger.error("ProjectHomeTraded: Error: #{inspect(error)}")
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
