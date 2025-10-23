defmodule CortexIqDashboard.Schemas.ProviderStateTest do
  use CortexIqDashboard.DataCase
  alias CortexIqDashboard.Schemas.ProviderState

  describe "changeset/2" do
    test "valid changeset with all fields" do
      attrs = %{
        provider_id: "provider_a",
        provider_name: "Steady Eddie Energy",
        strategy: "steady_eddie",
        active_contracts: 25,
        market_share_percent: 50.0,
        day_buy_price: 0.15,
        night_buy_price: 0.08,
        day_sell_price: 0.10,
        night_sell_price: 0.05,
        switching_discount: 15.0,
        last_event_at: ~U[2025-10-22 12:00:00Z]
      }

      changeset = ProviderState.changeset(%ProviderState{}, attrs)

      assert changeset.valid?
      assert changeset.changes.provider_id == "provider_a"
      assert changeset.changes.provider_name == "Steady Eddie Energy"
      assert changeset.changes.active_contracts == 25
      assert changeset.changes.market_share_percent == 50.0
    end

    test "valid changeset with minimal fields" do
      attrs = %{provider_id: "provider_a"}

      changeset = ProviderState.changeset(%ProviderState{}, attrs)

      assert changeset.valid?
      assert changeset.changes.provider_id == "provider_a"
    end

    test "invalid changeset without provider_id" do
      changeset = ProviderState.changeset(%ProviderState{}, %{provider_name: "Test"})

      refute changeset.valid?
      assert %{provider_id: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "database operations" do
    test "can insert and retrieve provider state" do
      attrs = %{
        provider_id: "provider_a",
        provider_name: "Steady Eddie Energy",
        strategy: "steady_eddie",
        day_buy_price: 0.15,
        active_contracts: 10
      }

      {:ok, provider_state} =
        %ProviderState{}
        |> ProviderState.changeset(attrs)
        |> Repo.insert()

      retrieved = Repo.get(ProviderState, "provider_a")

      assert retrieved.provider_id == "provider_a"
      assert retrieved.provider_name == "Steady Eddie Energy"
      assert retrieved.day_buy_price == 0.15
      assert retrieved.active_contracts == 10
    end

    test "can upsert provider state with new prices" do
      attrs = %{
        provider_id: "provider_a",
        provider_name: "Steady Eddie Energy",
        day_buy_price: 0.15
      }

      # First insert
      %ProviderState{}
      |> ProviderState.changeset(attrs)
      |> Repo.insert()

      # Upsert with new price
      updated_attrs = %{
        provider_id: "provider_a",
        provider_name: "Steady Eddie Energy",
        day_buy_price: 0.20
      }

      %ProviderState{}
      |> ProviderState.changeset(updated_attrs)
      |> Repo.insert(
        on_conflict: {:replace, [:day_buy_price, :updated_at]},
        conflict_target: :provider_id
      )

      retrieved = Repo.get(ProviderState, "provider_a")
      assert retrieved.day_buy_price == 0.20
    end

    test "can calculate market share" do
      # Insert multiple providers
      for {provider_id, contracts} <- [
        {"provider_a", 25},
        {"provider_b", 15},
        {"provider_c", 10}
      ] do
        %ProviderState{}
        |> ProviderState.changeset(%{
          provider_id: provider_id,
          active_contracts: contracts,
          market_share_percent: contracts / 50 * 100
        })
        |> Repo.insert()
      end

      providers = Repo.all(ProviderState)
      total_share = Enum.sum(Enum.map(providers, & &1.market_share_percent))

      assert_in_delta total_share, 100.0, 0.1
    end
  end
end
