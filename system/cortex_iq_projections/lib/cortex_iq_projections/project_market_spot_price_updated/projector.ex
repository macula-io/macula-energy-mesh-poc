defmodule CortexIqProjections.ProjectMarketSpotPriceUpdated.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.market.spot_price_updated events.

  Projects market.spot_price_updated events
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
    Logger.info("ProjectMarketSpotPriceUpdated.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_market_spot_price_updated(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_market_spot_price_updated(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    provider_id = kwargs["provider_id"]
    buy_price = kwargs["buy_price"]
    sell_price = kwargs["sell_price"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    Repo.insert!(
      %ProviderState{provider_id: provider_id},
      on_conflict: [
        set: [
          spot_buy_price: buy_price,
          spot_sell_price: sell_price,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :provider_id
    )
  rescue
    error ->
      Logger.error("VerticalSliceGenerator: Error: #{inspect(error)}")
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
