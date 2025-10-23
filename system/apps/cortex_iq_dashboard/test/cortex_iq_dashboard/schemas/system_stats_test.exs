defmodule CortexIqDashboard.Schemas.SystemStatsTest do
  use CortexIqDashboard.DataCase
  alias CortexIqDashboard.Schemas.SystemStats

  describe "changeset/2" do
    test "valid changeset with all fields" do
      attrs = %{
        id: 1,
        total_homes: 50,
        total_providers: 5,
        total_production_kwh: 1000.0,
        total_consumption_kwh: 800.0,
        total_energy_bought_kwh: 500.0,
        total_energy_sold_kwh: 200.0,
        total_cost_paid: 75.0,
        total_revenue_received: 20.0,
        contract_switches_count: 10,
        avg_battery_percent: 65.5,
        simulation_time: ~U[2025-06-15 12:00:00Z],
        simulation_speed: 105_120
      }

      changeset = SystemStats.changeset(%SystemStats{}, attrs)

      assert changeset.valid?
      assert changeset.changes.total_homes == 50
      assert changeset.changes.total_providers == 5
      assert changeset.changes.avg_battery_percent == 65.5
    end

    test "valid changeset with partial fields" do
      attrs = %{total_homes: 50, total_providers: 5}

      changeset = SystemStats.changeset(%SystemStats{}, attrs)

      assert changeset.valid?
      assert changeset.changes.total_homes == 50
    end

    test "can update existing stats" do
      stats = %SystemStats{id: 1, total_homes: 50, contract_switches_count: 5}
      attrs = %{contract_switches_count: 10, total_homes: 55}

      changeset = SystemStats.changeset(stats, attrs)

      assert changeset.valid?
      assert changeset.changes.contract_switches_count == 10
      assert changeset.changes.total_homes == 55
    end
  end

  describe "database operations" do
    test "can insert and retrieve system stats" do
      attrs = %{
        id: 1,
        total_homes: 50,
        total_providers: 5,
        total_production_kwh: 1000.0,
        avg_battery_percent: 70.0
      }

      {:ok, stats} =
        %SystemStats{}
        |> SystemStats.changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get(SystemStats, 1)

      assert retrieved.id == 1
      assert retrieved.total_homes == 50
      assert retrieved.total_providers == 5
      assert retrieved.avg_battery_percent == 70.0
    end

    test "can upsert system stats (only one row exists)" do
      # First insert
      %SystemStats{}
      |> SystemStats.changeset(%{id: 1, total_homes: 50})
      |> Repo.insert()

      # Upsert with new values
      %SystemStats{}
      |> SystemStats.changeset(%{id: 1, total_homes: 60, contract_switches_count: 5})
      |> Repo.insert(
        on_conflict: {:replace_all_except, [:id, :inserted_at]},
        conflict_target: :id
      )

      retrieved = Repo.get(SystemStats, 1)
      assert retrieved.total_homes == 60
      assert retrieved.contract_switches_count == 5
    end

    test "can increment contract switches" do
      # Insert initial stats
      %SystemStats{}
      |> SystemStats.changeset(%{id: 1, contract_switches_count: 5})
      |> Repo.insert()

      # Increment
      from(s in SystemStats, where: s.id == 1)
      |> Repo.update_all(inc: [contract_switches_count: 1])

      retrieved = Repo.get(SystemStats, 1)
      assert retrieved.contract_switches_count == 6
    end

    test "tracks simulation time" do
      sim_time = ~U[2025-06-15 14:30:00Z]

      %SystemStats{}
      |> SystemStats.changeset(%{
        id: 1,
        simulation_time: sim_time,
        simulation_speed: 105_120
      })
      |> Repo.insert()

      retrieved = Repo.get(SystemStats, 1)
      assert DateTime.compare(retrieved.simulation_time, sim_time) == :eq
      assert retrieved.simulation_speed == 105_120
    end
  end
end
