defmodule CortexIqDashboard.EventAggregatorTest do
  use CortexIqDashboard.DataCase
  alias CortexIqDashboard.EventAggregator
  alias CortexIqDashboard.Schemas.{HomeState, ProviderState, SystemStats}

  setup do
    # Initialize system stats
    Repo.insert!(%SystemStats{id: 1}, on_conflict: :nothing, conflict_target: :id)
    :ok
  end

  describe "home production events" do
    test "creates home state on first production event" do
      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.production"},
        kwargs: %{"watts" => 3500.0}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})

      # Give it a moment to process
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home != nil
      assert home.home_id == "home_0001"
      assert home.production_kw == 3.5
    end

    test "updates existing home state production" do
      # Insert initial home
      Repo.insert!(%HomeState{
        home_id: "home_0001",
        location: "Brussels",
        production_kw: 1.0
      })

      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.production"},
        kwargs: %{"watts" => 5000.0}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home.production_kw == 5.0
    end
  end

  describe "home consumption events" do
    test "updates consumption" do
      Repo.insert!(%HomeState{home_id: "home_0001", location: "Brussels"})

      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.consumption"},
        kwargs: %{"watts" => 1200.0}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home.consumption_kw == 1.2
    end
  end

  describe "home battery events" do
    test "updates battery percentage" do
      Repo.insert!(%HomeState{home_id: "home_0001", location: "Brussels"})

      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.storage"},
        kwargs: %{"battery_percent" => 75.5}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home.battery_percent == 75.5
    end
  end

  describe "home balance events" do
    test "updates energy balance" do
      Repo.insert!(%HomeState{home_id: "home_0001", location: "Brussels"})

      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.balance"},
        kwargs: %{
          "energy_bought_kwh" => 100.0,
          "energy_sold_kwh" => 50.0,
          "net_balance_kwh" => 50.0,
          "cost_paid" => 15.0,
          "revenue_received" => 5.0,
          "net_cost" => 10.0
        }
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home.energy_bought_kwh == 100.0
      assert home.energy_sold_kwh == 50.0
      assert home.net_balance_kwh == 50.0
      assert home.net_cost == 10.0
    end
  end

  describe "home contract events" do
    test "updates contract information" do
      Repo.insert!(%HomeState{home_id: "home_0001", location: "Brussels"})

      event_data = %{
        details: %{"topic" => "energy.hub.home.home_0001.contract"},
        kwargs: %{
          "provider_id" => "provider_a",
          "contract_id" => "contract_123",
          "end_date" => "2025-12-31T23:59:59Z"
        }
      }

      send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      Process.sleep(100)

      home = Repo.get(HomeState, "home_0001")
      assert home.provider_id == "provider_a"
      assert home.contract_id == "contract_123"
      assert home.contract_expires_at != nil
    end
  end

  describe "provider contract offer events" do
    test "creates provider state on first offer" do
      event_data = %{
        details: %{"topic" => "energy.hub.provider.provider_a.contract_offer"},
        kwargs: %{
          "provider_name" => "Steady Eddie Energy",
          "strategy" => "steady_eddie",
          "day_buy_price" => 0.15,
          "night_buy_price" => 0.08,
          "day_sell_price" => 0.10,
          "night_sell_price" => 0.05,
          "switching_discount" => 15.0
        }
      }

      send(EventAggregator, {:wamp_event, "energy.hub.provider.", event_data})
      Process.sleep(100)

      provider = Repo.get(ProviderState, "provider_a")
      assert provider != nil
      assert provider.provider_name == "Steady Eddie Energy"
      assert provider.day_buy_price == 0.15
      assert provider.switching_discount == 15.0
    end

    test "updates existing provider with new prices" do
      Repo.insert!(%ProviderState{
        provider_id: "provider_a",
        provider_name: "Steady Eddie Energy",
        day_buy_price: 0.15
      })

      event_data = %{
        details: %{"topic" => "energy.hub.provider.provider_a.contract_offer"},
        kwargs: %{
          "provider_name" => "Steady Eddie Energy",
          "strategy" => "steady_eddie",
          "day_buy_price" => 0.20
        }
      }

      send(EventAggregator, {:wamp_event, "energy.hub.provider.", event_data})
      Process.sleep(100)

      provider = Repo.get(ProviderState, "provider_a")
      assert provider.day_buy_price == 0.20
    end
  end

  describe "market share calculation" do
    test "calculates market share correctly" do
      # Insert homes with contracts
      for {home_id, provider_id} <- [
        {"home_0001", "provider_a"},
        {"home_0002", "provider_a"},
        {"home_0003", "provider_a"},
        {"home_0004", "provider_b"},
        {"home_0005", "provider_b"}
      ] do
        Repo.insert!(%HomeState{
          home_id: home_id,
          location: "Brussels",
          provider_id: provider_id
        })
      end

      # Insert providers
      Repo.insert!(%ProviderState{provider_id: "provider_a"})
      Repo.insert!(%ProviderState{provider_id: "provider_b"})

      # Trigger market share update (via provider offer event)
      event_data = %{
        details: %{"topic" => "energy.hub.provider.provider_a.contract_offer"},
        kwargs: %{"provider_name" => "Provider A"}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.provider.", event_data})
      Process.sleep(100)

      provider_a = Repo.get(ProviderState, "provider_a")
      provider_b = Repo.get(ProviderState, "provider_b")

      assert provider_a.active_contracts == 3
      assert provider_b.active_contracts == 2
      assert_in_delta provider_a.market_share_percent, 60.0, 0.1
      assert_in_delta provider_b.market_share_percent, 40.0, 0.1
    end
  end

  describe "simulation time events" do
    test "updates simulation time and speed" do
      event_data = %{
        details: %{"topic" => "energy.hub.simulation.time"},
        kwargs: %{
          "simulation_time" => "2025-06-15T14:30:00Z",
          "speed" => 105_120
        }
      }

      send(EventAggregator, {:wamp_event, "energy.hub.simulation.", event_data})
      Process.sleep(100)

      stats = Repo.get(SystemStats, 1)
      assert stats.simulation_speed == 105_120
      assert stats.simulation_time != nil
    end
  end

  describe "contract switch events" do
    test "increments contract switches counter" do
      # Get initial count
      initial_stats = Repo.get(SystemStats, 1)
      initial_count = initial_stats.contract_switches_count || 0

      event_data = %{
        details: %{"topic" => "energy.hub.market.contract.switched"},
        kwargs: %{"home_id" => "home_0001"}
      }

      send(EventAggregator, {:wamp_event, "energy.hub.market.", event_data})
      Process.sleep(100)

      stats = Repo.get(SystemStats, 1)
      assert stats.contract_switches_count == initial_count + 1
    end
  end

  describe "event processing performance" do
    test "processes multiple events efficiently" do
      start_time = System.monotonic_time(:millisecond)

      # Send 100 events
      for i <- 1..100 do
        event_data = %{
          details: %{"topic" => "energy.hub.home.home_#{String.pad_leading("#{i}", 4, "0")}.production"},
          kwargs: %{"watts" => :rand.uniform(5000)}
        }

        send(EventAggregator, {:wamp_event, "energy.hub.home.", event_data})
      end

      # Wait for processing
      Process.sleep(500)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should process 100 events in under 1 second
      assert duration < 1000

      # Verify homes were created
      home_count = Repo.aggregate(HomeState, :count)
      assert home_count == 100
    end
  end
end
