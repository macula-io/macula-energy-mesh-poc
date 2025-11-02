defmodule CortexIqProjections.ProjectMarketContractExpired.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.market.contract_expired events.

  Projects market.contract_expired events
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
    Logger.info("ProjectMarketContractExpired.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_market_contract_expired(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_market_contract_expired(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    contract_id = kwargs["contract_id"]
    home_id = kwargs["home_id"]
    provider_id = kwargs["provider_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    Repo.insert!(%ContractEvent{
      contract_id: contract_id,
      home_id: home_id,
      provider_id: provider_id,
      event_type: "expired",
      simulation_time: simulation_time
    })
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
