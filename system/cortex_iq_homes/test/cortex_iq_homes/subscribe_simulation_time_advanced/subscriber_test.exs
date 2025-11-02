defmodule CortexIqHomes.SubscribeSimulationTimeAdvanced.SubscriberTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeSimulationTimeAdvanced.Subscriber

  describe "init/1" do
    test "initializes state with wamp_client and home_id" do
      opts = [wamp_client: :test_client, home_id: "test-home-123"]

      assert {:ok, state} = Subscriber.init(opts)
      assert state.wamp_client == :test_client
      assert state.home_id == "test-home-123"
    end

    test "schedules subscription after 2 seconds" do
      opts = [wamp_client: :test_client, home_id: "test-home"]

      {:ok, _state} = Subscriber.init(opts)

      # Verify :subscribe message is scheduled
      assert_receive :subscribe, 2100
    end
  end

  describe "handle_info/2 with :event" do
    test "parses valid ISO8601 simulation time" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      event_data = %{
        kwargs: %{"simulation_time" => "2025-01-15T10:30:00Z"}
      }

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "handles nil simulation time gracefully" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      event_data = %{kwargs: %{}}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "handles invalid ISO8601 format gracefully" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      event_data = %{kwargs: %{"simulation_time" => "invalid-date"}}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "handles missing kwargs gracefully" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      event_data = %{}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end
  end
end
