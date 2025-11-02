defmodule CortexIqHomes.SubscribeContractConfirmed.SystemTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeContractConfirmed.System

  describe "init/1" do
    test "initializes with WAMP client and subscriber as children" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://localhost:18080/ws"]

      assert {:ok, {supervisor_flags, children}} = System.init(opts)
      assert Map.get(supervisor_flags, :strategy) == :rest_for_one
      assert length(children) == 2
    end

    test "uses :rest_for_one supervision strategy" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://test:18080/ws"]

      assert {:ok, {%{strategy: :rest_for_one}, _children}} = System.init(opts)
    end
  end
end
