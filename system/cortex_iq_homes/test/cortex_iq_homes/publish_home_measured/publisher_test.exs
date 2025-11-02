defmodule CortexIqHomes.PublishHomeMeasured.PublisherTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.PublishHomeMeasured.Publisher

  describe "init/1" do
    test "initializes state with wamp_client and home_id" do
      opts = [wamp_client: :test_client, home_id: "test-home-123"]

      assert {:ok, state} = Publisher.init(opts)
      assert state.wamp_client == :test_client
      assert state.home_id == "test-home-123"
    end
  end

  describe "whereis/1" do
    test "returns nil when publisher not found" do
      assert Publisher.whereis("nonexistent-home") == nil
    end
  end

  describe "publish/2" do
    test "handles missing publisher gracefully" do
      # Should not crash when publisher doesn't exist
      assert Publisher.publish("nonexistent-home", %{data: "test"}) == :ok
    end
  end

  describe "handle_info/2 with :publish" do
    test "returns noreply tuple" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      data = %{power_w: 1000, timestamp: "2025-01-15T10:30:00Z"}

      assert {:noreply, ^state} = Publisher.handle_info({:publish, data}, state)
    end

    test "handles empty data gracefully" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      assert {:noreply, ^state} = Publisher.handle_info({:publish, %{}}, state)
    end

    test "maintains state after publication" do
      initial_state = %{wamp_client: :test_client, home_id: "test-home", custom: "value"}
      data = %{test: "data"}

      assert {:noreply, returned_state} = Publisher.handle_info({:publish, data}, initial_state)
      assert returned_state == initial_state
    end
  end
end
