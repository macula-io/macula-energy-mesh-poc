defmodule CortexIqHomes.HomeBotTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.HomeBot
  alias CortexIqCore.Home

  describe "init/1" do
    test "initializes state with home configuration" do
      home = %Home{
        id: "test-home-123",
        name: "Test Home",
        location: %{
          street: "Test Street 1",
          city: "Test City",
          postal_code: "1000",
          region: :flanders,
          latitude: 50.0,
          longitude: 4.0
        },
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0,
        current_contract_id: nil
      }

      opts = [
        home: home,
        home_id: home.id,
        realm: "test.realm",
        bondy_url: "ws://localhost:18080/ws"
      ]

      assert {:ok, state} = HomeBot.init(opts)
      assert state.home_id == "test-home-123"
      assert state.home == home
      assert state.realm == "test.realm"
    end

    test "initializes battery state between 50-80% charge" do
      home = %Home{
        id: "test-home",
        name: "Test Home",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0,
        current_contract_id: nil
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, state} = HomeBot.init(opts)

      # Battery should be 50-80% of capacity (5-8 kWh)
      assert state.battery_state_kwh >= 5.0
      assert state.battery_state_kwh <= 8.0
    end

    test "initializes with nil simulation time" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, state} = HomeBot.init(opts)

      assert state.current_simulation_time == nil
      assert state.current_contract == nil
      assert state.energy_balance == nil
    end

    test "initializes flexible load to 0.1 kWh" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, state} = HomeBot.init(opts)

      assert state.flexible_load_kwh == 0.1
      assert state.flexible_load_schedule == %{}
    end

    test "initializes cumulative meter readings to zero" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, state} = HomeBot.init(opts)

      assert state.cumulative_import_kwh == 0.0
      assert state.cumulative_export_kwh == 0.0
    end

    test "initializes CortexIQ financial tracking to zero" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, state} = HomeBot.init(opts)

      assert state.cortexiq_total_commission == 0.0
      assert state.cortexiq_total_savings == 0.0
      assert state.cortexiq_net_savings == 0.0
      assert state.contract_switches_count == 0
    end

    test "schedules subscription with staggered delay" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, _state} = HomeBot.init(opts)

      # Should receive :subscribe message after delay (up to 30 seconds by default)
      assert_receive :subscribe, 31_000
    end

    test "schedules first update" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      opts = [home: home, home_id: home.id, realm: "test.realm", bondy_url: "ws://test"]

      {:ok, _state} = HomeBot.init(opts)

      # Should receive :update message after 100ms
      assert_receive :update, 200
    end
  end

  describe "whereis/1" do
    test "returns nil when home not found" do
      assert HomeBot.whereis("nonexistent-home") == nil
    end
  end

  describe "handle_call(:get_state)" do
    test "returns current state" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        current_simulation_time: nil
      }

      assert {:reply, ^state, ^state} = HomeBot.handle_call(:get_state, self(), state)
    end
  end

  describe "handle_info(:update)" do
    test "skips operations when paused" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      # Set paused_until to future time
      future_time = System.monotonic_time(:millisecond) + 10_000

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        paused_until: future_time,
        current_simulation_time: nil
      }

      # Update should not modify state while paused
      assert {:noreply, returned_state} = HomeBot.handle_info(:update, state)
      assert returned_state.paused_until == future_time
    end

    test "skips operations when not connected" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        connected: false,
        current_simulation_time: DateTime.utc_now()
      }

      # Update should not perform simulation when disconnected
      assert {:noreply, _returned_state} = HomeBot.handle_info(:update, state)
    end

    test "schedules next update" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        paused_until: nil,
        current_simulation_time: nil
      }

      {:noreply, _new_state} = HomeBot.handle_info(:update, state)

      # Should receive next :update message
      assert_receive :update, 200
    end
  end

  describe "handle_info({:wamp_event, ...})" do
    test "handles simulation time update" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        current_simulation_time: nil
      }

      sim_time = "2025-01-15T10:30:00Z"
      kwargs = %{"simulation_time" => sim_time}

      assert {:noreply, new_state} =
               HomeBot.handle_info(
                 {:wamp_event, "be.cortexiq.simulation.time_advanced", [], kwargs, %{}},
                 state
               )

      assert new_state.current_simulation_time != nil
    end

    test "handles simulation reset" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        battery_state_kwh: 5.0,
        current_simulation_time: DateTime.utc_now(),
        cumulative_import_kwh: 100.0,
        cumulative_export_kwh: 50.0
      }

      assert {:noreply, new_state} =
               HomeBot.handle_info(
                 {:wamp_event, "be.cortexiq.simulation.reset", [], %{}, %{}},
                 state
               )

      assert new_state.current_simulation_time == nil
      assert new_state.cumulative_import_kwh == 0.0
      assert new_state.cumulative_export_kwh == 0.0
      assert new_state.paused_until != nil
    end

    test "handles contract offer" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home,
        provider_offers: %{}
      }

      kwargs = %{
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
      }

      assert {:noreply, new_state} =
               HomeBot.handle_info(
                 {:wamp_event, "be.cortexiq.market.contract_proposed", [], kwargs, %{}},
                 state
               )

      assert map_size(new_state.provider_offers) == 1
      assert Map.has_key?(new_state.provider_offers, "provider_a")
    end

    test "ignores unknown WAMP events" do
      home = %Home{
        id: "test-home",
        name: "Test",
        location: %{city: "Test", postal_code: "1000", region: :flanders},
        solar_capacity_kw: 5.0,
        battery_capacity_kwh: 10.0
      }

      state = %HomeBot{
        home_id: home.id,
        home: home
      }

      assert {:noreply, ^state} =
               HomeBot.handle_info(
                 {:wamp_event, "unknown.topic", [], %{}, %{}},
                 state
               )
    end
  end
end
