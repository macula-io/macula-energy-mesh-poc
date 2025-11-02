defmodule CortexIqProjections.ProjectSimulationReset.Projector do
  @moduledoc """
  GenServer projector for be.cortexiq.simulation.reset events.

  Projects simulation.reset events (clear all state)
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
    Logger.info("ProjectSimulationReset.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_simulation_reset(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_simulation_reset(_event_data) do
    # Clear all projection state
    Logger.warning("Simulation reset - clearing all projection state")

    # Truncate all tables
    Repo.query!("TRUNCATE home_states CASCADE")
    Repo.query!("TRUNCATE provider_states CASCADE")
    Repo.query!("TRUNCATE energy_events CASCADE")
    Repo.query!("TRUNCATE energy_trades CASCADE")
    Repo.query!("TRUNCATE contract_events CASCADE")
    Repo.query!("TRUNCATE contract_switches CASCADE")

    # Reset system stats
    Repo.insert!(
      %SystemStats{id: 1},
      on_conflict: [
        set: [
          simulation_time: nil,
          simulation_speed: 105_120,
          homes_connected_count: 0,
          contract_switches_count: 0,
          cortexiq_total_commission: 0.0,
          cortexiq_total_savings: 0.0,
          cortexiq_net_savings: 0.0,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :id
    )

    Logger.info("✓ Simulation state reset complete")

    # Publish zero totals immediately after reset
    publish_zero_totals()
  rescue
    error ->
      Logger.error("ProjectSimulationReset: Error: #{inspect(error)}")
  end


  # Helper Functions

  defp publish_zero_totals do
    Logger.info("ProjectSimulationReset: Publishing zero totals after reset")

    zero_totals = %{
      "total_homes" => 0,
      "total_production_w" => 0,
      "total_consumption_w" => 0,
      "total_net_w" => 0,
      "total_battery_capacity_wh" => 0,
      "total_battery_stored_wh" => 0,
      "avg_battery_percent" => 0,
      "total_sold_to_grid_wh" => 0,
      "total_bought_from_grid_wh" => 0,
      "total_cost_eur" => 0,
      "total_revenue_eur" => 0,
      "net_cost_eur" => 0,
      "simulation_time" => nil,
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    topic = "be.cortexiq.projections.totals_calculated"

    case MaculaSdk.Wamp.Client.publish(:wamp_calculate_system_totals, topic, [zero_totals], %{}) do
      :ok ->
        Logger.info("ProjectSimulationReset: Published zero totals")
      {:error, reason} ->
        Logger.error("ProjectSimulationReset: Failed to publish zero totals: #{inspect(reason)}")
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
