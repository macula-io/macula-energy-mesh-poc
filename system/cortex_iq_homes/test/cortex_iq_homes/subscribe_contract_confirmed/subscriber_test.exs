defmodule CortexIqHomes.SubscribeContractConfirmed.SubscriberTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeContractConfirmed.Subscriber

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
      assert_receive :subscribe, 2100
    end
  end

  describe "handle_info/2 with :event" do
    test "processes contract confirmed event" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      event_data = %{kwargs: %{
        "home_id" => "test-home",
        "contract_id" => "contract_123",
        "provider_id" => "provider_a",
        "start_date" => "2025-01-15T00:00:00Z",
        "end_date" => "2026-01-15T00:00:00Z",
        "reason" => "new"
      }}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "ignores events for other homes" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      event_data = %{kwargs: %{
        "home_id" => "other-home",
        "contract_id" => "contract_123",
        "provider_id" => "provider_a",
        "start_date" => "2025-01-15T00:00:00Z",
        "end_date" => "2026-01-15T00:00:00Z",
        "reason" => "new"
      }}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end
  end
end
