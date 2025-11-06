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

  defp project_market_contract_proposed(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    provider_id = kwargs["provider_id"]
    provider_name = kwargs["provider_name"]
    strategy = kwargs["strategy"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Update provider state with latest contract offer pricing
    # This allows dashboard to show current pricing without querying individual offers
    updates = %{
      provider_name: provider_name,
      strategy: strategy,
      last_event_at: simulation_time,
      updated_at: DateTime.utc_now()
    }

    # Add pricing fields based on contract type
    updates = case kwargs["contract_type"] do
      "static" ->
        Map.merge(updates, %{
          day_buy_price: kwargs["day_buy_price"],
          night_buy_price: kwargs["night_buy_price"],
          day_sell_price: kwargs["day_sell_price"],
          night_sell_price: kwargs["night_sell_price"],
          switching_discount: kwargs["switching_discount"],
          minimum_monthly_kwh: kwargs["minimum_monthly_kwh"]
        })

      "dynamic" ->
        # For dynamic contracts, we store the markup/markdown
        # Dashboard can show this differently
        Map.merge(updates, %{
          switching_discount: kwargs["switching_discount"],
          minimum_monthly_kwh: kwargs["minimum_monthly_kwh"]
        })

      _ ->
        updates
    end

    Repo.insert!(
      %ProviderState{provider_id: provider_id},
      on_conflict: [set: Enum.to_list(updates)],
      conflict_target: :provider_id
    )

    :ok
  rescue
    error ->
      Logger.error("ProjectMarketContractProposed: Error: #{inspect(error)}")
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
