defmodule CortexIqProjections.ProjectMarketContractProposed.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.market.contract_proposed events.

  Projects market.contract_proposed events
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
    Logger.info("ProjectMarketContractProposed.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_market_contract_proposed(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_market_contract_proposed(_event_data) do
    # Contract proposals are transient offers that don't need to be persisted.
    # The contract_events table is for actual contract lifecycle events:
    # - signed: when a home accepts an offer
    # - switched: when a home switches providers
    # - expired: when a contract reaches end date
    #
    # Proposals are just offers published by providers via WAMP.
    # They don't have a contract_id yet (no contract exists until accepted).
    :ok
  end


  # Helper Functions

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} ->
        # Convert to microseconds and back to ensure 6-digit precision for Ecto
        datetime
        |> DateTime.to_unix(:microsecond)
        |> DateTime.from_unix!(:microsecond)
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
