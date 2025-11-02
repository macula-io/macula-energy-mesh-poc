defmodule CortexIqProjections.ProjectMarketContractConfirmed.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.market.contract_confirmed events.

  Projects market.contract_confirmed events
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
    Logger.info("ProjectMarketContractConfirmed.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_market_contract_confirmed(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_market_contract_confirmed(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    provider_id = kwargs["provider_id"]
    contract_id = kwargs["contract_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update home state with new contract
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          provider_id: provider_id,
          contract_id: contract_id,
          contract_expires_at: parse_datetime(kwargs["end_date"]),
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # Insert contract event
    Repo.insert!(%ContractEvent{
      contract_id: contract_id,
      home_id: home_id,
      provider_id: provider_id,
      event_type: "confirmed",
      simulation_time: simulation_time,
      start_date: parse_datetime(kwargs["start_date"]),
      end_date: parse_datetime(kwargs["end_date"]),
      day_buy_price: kwargs["day_buy_price"],
      night_buy_price: kwargs["night_buy_price"],
      day_sell_price: kwargs["day_sell_price"],
      night_sell_price: kwargs["night_sell_price"],
      switching_discount: kwargs["switching_discount"]
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
