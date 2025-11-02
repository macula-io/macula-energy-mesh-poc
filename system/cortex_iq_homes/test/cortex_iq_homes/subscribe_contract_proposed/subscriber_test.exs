defmodule CortexIqHomes.SubscribeContractProposed.SubscriberTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.SubscribeContractProposed.Subscriber

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
    test "processes event data with valid contract offer" do
      state = %{wamp_client: :test_client, home_id: "test-home"}

      event_data = %{kwargs: %{
        "provider_id" => "provider_a",
        "offer_id" => "offer_123",
        "day_buy_price" => 0.15,
        "night_buy_price" => 0.08,
        "day_sell_price" => 0.10,
        "night_sell_price" => 0.05,
        "switching_discount" => 25.0,
        "minimum_monthly_kwh" => 100,
        "duration_months" => 12,
        "valid_from" => "2025-01-15T10:30:00Z"
      }}

      assert {:noreply, ^state} = Subscriber.handle_info({:event, event_data}, state)
    end

    test "handles missing kwargs with error" do
      state = %{wamp_client: :test_client, home_id: "test-home"}
      event_data = %{kwargs: %{}}

      # This will fail to parse but should not crash the GenServer
      assert_raise KeyError, fn ->
        Subscriber.handle_info({:event, event_data}, state)
      end
    end
  end
end
