defmodule CortexIqProjections.ProjectHomeConnected.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.home.connected events.

  Projects home.connected events (WAMP connection)

  Status handling: Sets CONNECTED flag (4), unsets DISCONNECTED flag (8).
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
    Logger.info("ProjectHomeConnected.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_home_connected(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_home_connected(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # Get current status or default to 0
    current_status = case Repo.get(HomeState, home_id) do
      nil -> 0
      home -> home.status || 0
    end

    # Set CONNECTED flag, unset DISCONNECTED flag
    new_status = HomeStatus.connect(current_status)

    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          connected_at: simulation_time,
          disconnected_at: nil,
          status: new_status,
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    Logger.debug("ProjectHomeConnected: Updated #{home_id} status from #{current_status} to #{new_status} (#{HomeStatus.to_string(new_status)})")
  rescue
    error ->
      Logger.error("ProjectHomeConnected: Error: #{inspect(error)}")
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
