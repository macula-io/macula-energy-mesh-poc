defmodule CortexIqDashboard.Schemas.HomeStateTest do
  use CortexIqDashboard.DataCase
  alias CortexIqDashboard.Schemas.HomeState

  describe "changeset/2" do
    test "valid changeset with all fields" do
      attrs = %{
        home_id: "home_0001",
        location: "Brussels",
        postal_code: "1000",
        region: "brussels",
        production_kw: 3.5,
        consumption_kw: 1.2,
        battery_percent: 75.0,
        battery_kwh: 7.5,
        battery_capacity_kwh: 10.0,
        provider_id: "provider_a",
        contract_id: "contract_123",
        contract_expires_at: ~U[2025-12-31 23:59:59Z],
        energy_bought_kwh: 100.0,
        energy_sold_kwh: 50.0,
        net_balance_kwh: 50.0,
        cost_paid: 15.0,
        revenue_received: 5.0,
        net_cost: 10.0,
        last_event_at: ~U[2025-10-22 12:00:00Z]
      }

      changeset = HomeState.changeset(%HomeState{}, attrs)

      assert changeset.valid?
      assert changeset.changes.home_id == "home_0001"
      assert changeset.changes.production_kw == 3.5
      assert changeset.changes.battery_percent == 75.0
    end

    test "valid changeset with minimal fields" do
      attrs = %{home_id: "home_0001"}

      changeset = HomeState.changeset(%HomeState{}, attrs)

      assert changeset.valid?
      assert changeset.changes.home_id == "home_0001"
    end

    test "invalid changeset without home_id" do
      changeset = HomeState.changeset(%HomeState{}, %{location: "Brussels"})

      refute changeset.valid?
      assert %{home_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "can update existing home state" do
      home_state = %HomeState{home_id: "home_0001", production_kw: 1.0}
      attrs = %{production_kw: 3.5, consumption_kw: 2.0}

      changeset = HomeState.changeset(home_state, attrs)

      assert changeset.valid?
      assert changeset.changes.production_kw == 3.5
      assert changeset.changes.consumption_kw == 2.0
    end
  end

  describe "database operations" do
    test "can insert and retrieve home state" do
      attrs = %{
        home_id: "home_0001",
        location: "Brussels",
        postal_code: "1000",
        region: "brussels",
        production_kw: 3.5,
        consumption_kw: 1.2,
        battery_percent: 75.0
      }

      {:ok, home_state} =
        %HomeState{}
        |> HomeState.changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get(HomeState, "home_0001")

      assert retrieved.home_id == "home_0001"
      assert retrieved.location == "Brussels"
      assert retrieved.production_kw == 3.5
      assert retrieved.battery_percent == 75.0
    end

    test "can upsert home state" do
      attrs = %{
        home_id: "home_0001",
        location: "Brussels",
        production_kw: 1.0
      }

      # First insert
      %HomeState{}
      |> HomeState.changeset(attrs)
      |> Repo.insert()

      # Upsert with new production value
      updated_attrs = %{
        home_id: "home_0001",
        location: "Brussels",
        production_kw: 5.0
      }

      %HomeState{}
      |> HomeState.changeset(updated_attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:production_kw, :updated_at]},
        conflict_target: :home_id
      )

      retrieved = Repo.get(HomeState, "home_0001")
      assert retrieved.production_kw == 5.0
    end

    test "can query by region" do
      # Insert homes in different regions
      for {home_id, region} <- [
        {"home_0001", "brussels"},
        {"home_0002", "brussels"},
        {"home_0003", "flanders"}
      ] do
        %HomeState{}
        |> HomeState.changeset(%{home_id: home_id, region: region})
        |> Repo.insert()
      end

      brussels_homes =
        HomeState
        |> where([h], h.region == "brussels")
        |> Repo.all()

      assert length(brussels_homes) == 2
    end

    test "can query by provider" do
      # Insert homes with different providers
      for {home_id, provider_id} <- [
        {"home_0001", "provider_a"},
        {"home_0002", "provider_a"},
        {"home_0003", "provider_b"}
      ] do
        %HomeState{}
        |> HomeState.changeset(%{home_id: home_id, provider_id: provider_id})
        |> Repo.insert()
      end

      provider_a_homes =
        HomeState
        |> where([h], h.provider_id == "provider_a")
        |> Repo.all()

      assert length(provider_a_homes) == 2
    end
  end
end
