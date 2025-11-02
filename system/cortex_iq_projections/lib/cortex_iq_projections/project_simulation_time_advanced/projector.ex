defmodule CortexIqProjections.ProjectSimulationTimeAdvanced.Projector do
  @moduledoc """
  GenServer projector for simulation.time_advanced events.

  ## Performance

  - Input rate: 1 event/sec (very low volume)
  - No batching needed - simple synchronous database writes
  - Updates system_stats table with current simulation time and speed

  ## Event Structure

  ```elixir
  %{
    kwargs: %{
      "simulation_time" => "2025-01-15T14:32:00Z",
      "speed" => 105_120,
      "real_elapsed_ms" => 150_000
    }
  }
  ```
  """
  use GenServer
  require Logger
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.SystemStats

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
    Logger.info("ProjectSimulationTimeAdvanced.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_time_advanced(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_time_advanced(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})
    simulation_time = parse_datetime(kwargs["simulation_time"])
    speed = kwargs["speed"] || 105_120

    Repo.insert!(
      %SystemStats{id: 1},
      on_conflict: [
        set: [
          simulation_time: simulation_time,
          simulation_speed: speed,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :id
    )
  rescue
    error ->
      Logger.error("ProjectSimulationTimeAdvanced.Projector: Error: #{inspect(error)}")
  end

  # Helper Functions

  defp parse_datetime(nil), do: DateTime.utc_now()

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
