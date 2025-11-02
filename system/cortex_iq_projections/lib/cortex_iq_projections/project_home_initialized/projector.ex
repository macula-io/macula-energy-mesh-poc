defmodule CortexIqProjections.ProjectHomeInitialized.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.home.initialized events.

  Projects home.initialized events (home creation)

  Status handling: Sets INITIALIZED flag (2), preserving RESERVED flag (1) if present.
  """
  use GenServer
  require Logger
  import Ecto.Query
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
  alias CortexIqDashboardSchemas.TimeSeries.{EnergyEvent, EnergyTrade, ContractEvent}
  alias CortexIqDashboardSchemas.HomeStatus

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
    Logger.info("ProjectHomeInitialized.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_home_initialized(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_home_initialized(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    name = kwargs["name"]
    iot_provider = kwargs["iot_provider"]
    location = kwargs["location"]
    postal_code = kwargs["postal_code"]
    region = kwargs["region"]
    solar_capacity_kw = kwargs["solar_capacity_kw"] || 5.0
    battery_capacity_kwh = kwargs["battery_capacity_kwh"] || 10.0
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Get current status or default to 0
    current_status = case Repo.get(HomeState, home_id) do
      nil -> 0
      home -> home.status || 0
    end

    # Set INITIALIZED flag (2), preserving existing flags (like RESERVED=1)
    new_status = HomeStatus.set_initialized(current_status)

    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          name: name,
          iot_provider: iot_provider,
          location: location,
          postal_code: postal_code,
          region: region,
          battery_capacity_kwh: battery_capacity_kwh,
          status: new_status,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    Logger.debug("ProjectHomeInitialized: Updated #{home_id} status from #{current_status} to #{new_status} (#{HomeStatus.to_string(new_status)})")
  rescue
    error ->
      Logger.error("ProjectHomeInitialized: Error: #{inspect(error)}")
      Logger.error("Event data: #{inspect(event_data)}")
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
