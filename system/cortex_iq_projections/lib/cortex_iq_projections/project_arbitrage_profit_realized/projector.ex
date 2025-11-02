defmodule CortexIqProjections.ProjectArbitrageProfitRealized.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.arbitrage.profit_realized events.

  Projects arbitrage.profit_realized events (battery arbitrage)
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
    Logger.info("ProjectArbitrageProfitRealized.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_arbitrage_profit_realized(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_arbitrage_profit_realized(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    profit = kwargs["profit"] || 0.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Could create separate arbitrage_profits table or add to home_state
    # For now, just log it
    Logger.info("Arbitrage profit realized: #{home_id} = $#{profit}")
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
