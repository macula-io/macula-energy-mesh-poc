defmodule CortexIqHomes.PublishHomeMeasured.SystemTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.PublishHomeMeasured.System

  describe "init/1" do
    test "initializes with WAMP client and publisher as children" do
      opts = [
        home_id: "test-home-123",
        realm: "test.realm",
        bondy_url: "ws://localhost:18080/ws"
      ]

      assert {:ok, {supervisor_flags, children}} = System.init(opts)
      assert Map.get(supervisor_flags, :strategy) == :rest_for_one
      assert length(children) == 2

      # Verify WAMP client is first child
      [wamp_child | _] = children
      assert %{id: :wamp_client} = wamp_child

      # Verify publisher is second child
      [_, publisher_child] = children
      assert %{id: _, start: {_, :start_link, _}} = publisher_child
    end

    test "uses :rest_for_one supervision strategy" do
      opts = [home_id: "test-home", realm: "test.realm", bondy_url: "ws://test:18080/ws"]

      assert {:ok, {%{strategy: :rest_for_one}, _children}} = System.init(opts)
    end

    test "creates unique WAMP client name based on home_id" do
      opts = [home_id: "test-home-123456789012", realm: "test.realm", bondy_url: "ws://test"]

      {:ok, {_flags, [wamp_child | _]}} = System.init(opts)

      # WAMP client should have unique name
      assert %{id: :wamp_client, start: {_, _, [wamp_opts]}} = wamp_child
      assert Keyword.has_key?(wamp_opts, :name)
    end
  end
end
