defmodule CortexIqHomes.HomeSupervisorTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.HomeSupervisor

  describe "init/1" do
    test "initializes with HomeBot and 15 vertical slice systems" do
      opts = [
        home_id: "test-home-123",
        realm: "test.realm",
        bondy_url: "ws://localhost:18080/ws"
      ]

      assert {:ok, {supervisor_flags, children}} = HomeSupervisor.init(opts)
      assert Map.get(supervisor_flags, :strategy) == :one_for_one

      # Should have 16 children: 1 HomeBot + 15 systems
      assert length(children) == 16

      # First child should be HomeBot
      [homebot_child | systems] = children
      assert %{id: CortexIqHomes.HomeBot, start: {_, :start_link, _}} = homebot_child

      # Remaining 15 should be system modules
      assert length(systems) == 15
    end

    test "uses :one_for_one supervision strategy" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://test"]

      assert {:ok, {%{strategy: :one_for_one}, _children}} = HomeSupervisor.init(opts)
    end

    test "includes all 5 subscriber systems" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://test"]

      {:ok, {_flags, children}} = HomeSupervisor.init(opts)

      subscriber_systems = [
        CortexIqHomes.SubscribeSimulationTimeAdvanced.System,
        CortexIqHomes.SubscribeContractProposed.System,
        CortexIqHomes.SubscribeSpotPriceUpdated.System,
        CortexIqHomes.SubscribeContractConfirmed.System,
        CortexIqHomes.SubscribeContractRejected.System
      ]

      Enum.each(subscriber_systems, fn system_module ->
        assert Enum.any?(children, fn
          %{id: ^system_module, type: :supervisor} -> true
          _ -> false
        end)
      end)
    end

    test "includes all 10 publisher systems" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://test"]

      {:ok, {_flags, children}} = HomeSupervisor.init(opts)

      publisher_systems = [
        CortexIqHomes.PublishHomeMeasured.System,
        CortexIqHomes.PublishHomeInitialized.System,
        CortexIqHomes.PublishHomeConnected.System,
        CortexIqHomes.PublishHomeDisconnected.System,
        CortexIqHomes.PublishContractSigned.System,
        CortexIqHomes.PublishContractSwitched.System,
        CortexIqHomes.PublishContractExpired.System,
        CortexIqHomes.PublishTradeExecuted.System,
        CortexIqHomes.PublishArbitrageProfit.System,
        CortexIqHomes.PublishBalanceUpdated.System
      ]

      Enum.each(publisher_systems, fn system_module ->
        assert Enum.any?(children, fn
          %{id: ^system_module, type: :supervisor} -> true
          _ -> false
        end)
      end)
    end
  end
end
