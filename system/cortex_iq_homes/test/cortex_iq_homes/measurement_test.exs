defmodule CortexIqHomes.MeasurementTest do
  use ExUnit.Case, async: true

  alias CortexIqHomes.Measurement

  describe "distribute_power_across_phases/2" do
    test "distributes power across three phases" do
      total_power = 3000.0
      phase_ratios = %{l1: 0.33, l2: 0.33, l3: 0.34}

      result = Measurement.distribute_power_across_phases(total_power, phase_ratios)

      assert is_map(result)
      assert Map.has_key?(result, :l1)
      assert Map.has_key?(result, :l2)
      assert Map.has_key?(result, :l3)
    end

    test "uses default ratios when not provided" do
      total_power = 3000.0
      phase_ratios = %{}

      result = Measurement.distribute_power_across_phases(total_power, phase_ratios)

      # Should use defaults (0.33, 0.33, 0.34)
      assert result.l1 == 990.0
      assert result.l2 == 990.0
      assert result.l3 == 1020.0
    end

    test "handles zero power" do
      result = Measurement.distribute_power_across_phases(0.0, %{})

      assert result.l1 == 0.0
      assert result.l2 == 0.0
      assert result.l3 == 0.0
    end

    test "total distributed power equals input power" do
      total_power = 5000.0
      phase_ratios = %{l1: 0.4, l2: 0.3, l3: 0.3}

      result = Measurement.distribute_power_across_phases(total_power, phase_ratios)

      sum = result.l1 + result.l2 + result.l3
      assert_in_delta sum, total_power, 0.01
    end
  end

  describe "calculate_voltage_per_phase/0" do
    test "returns voltage map for all phases" do
      result = Measurement.calculate_voltage_per_phase()

      assert is_map(result)
      assert Map.has_key?(result, :l1)
      assert Map.has_key?(result, :l2)
      assert Map.has_key?(result, :l3)
      assert Map.has_key?(result, :total)
    end

    test "voltages are around 230V nominal" do
      result = Measurement.calculate_voltage_per_phase()

      # Should be within ±2% of 230V (225.4V to 234.6V)
      assert result.l1 >= 225.0 and result.l1 <= 235.0
      assert result.l2 >= 225.0 and result.l2 <= 235.0
      assert result.l3 >= 225.0 and result.l3 <= 235.0
      assert result.total == 230.0
    end

    test "generates different values on each call (random variation)" do
      result1 = Measurement.calculate_voltage_per_phase()
      result2 = Measurement.calculate_voltage_per_phase()

      # Very unlikely to be exactly the same due to randomness
      assert result1.l1 != result2.l1 or result1.l2 != result2.l2 or result1.l3 != result2.l3
    end
  end

  describe "calculate_current/2" do
    test "calculates current from power and voltage (I = P / V)" do
      power_w = 2300.0
      voltage_v = 230.0

      result = Measurement.calculate_current(power_w, voltage_v)

      assert result == 10.0
    end

    test "handles zero power" do
      result = Measurement.calculate_current(0.0, 230.0)

      assert result == 0.0
    end

    test "returns 0 for zero voltage" do
      result = Measurement.calculate_current(2300.0, 0.0)

      assert result == 0.0
    end

    test "calculates realistic current values" do
      # Typical home: 3000W at 230V = ~13A
      power_w = 3000.0
      voltage_v = 230.0

      result = Measurement.calculate_current(power_w, voltage_v)

      assert_in_delta result, 13.04, 0.1
    end
  end

  describe "calculate_frequency/0" do
    test "returns frequency around 50Hz" do
      result = Measurement.calculate_frequency()

      # European grid: 50Hz ±0.2Hz
      assert result >= 49.8 and result <= 50.2
    end

    test "generates different values on each call (random variation)" do
      result1 = Measurement.calculate_frequency()
      result2 = Measurement.calculate_frequency()

      # Very unlikely to be exactly the same
      assert result1 != result2
    end
  end

  describe "generate_phase_ratios/0" do
    test "generates phase ratios that sum to 1.0" do
      result = Measurement.generate_phase_ratios()

      sum = result.l1 + result.l2 + result.l3
      assert_in_delta sum, 1.0, 0.0001
    end

    test "returns map with all phase keys" do
      result = Measurement.generate_phase_ratios()

      assert is_map(result)
      assert Map.has_key?(result, :l1)
      assert Map.has_key?(result, :l2)
      assert Map.has_key?(result, :l3)
    end

    test "all ratios are positive" do
      result = Measurement.generate_phase_ratios()

      assert result.l1 > 0
      assert result.l2 > 0
      assert result.l3 > 0
    end

    test "generates different ratios on each call (random)" do
      result1 = Measurement.generate_phase_ratios()
      result2 = Measurement.generate_phase_ratios()

      # Very unlikely to be exactly the same
      assert result1.l1 != result2.l1 or result1.l2 != result2.l2 or result1.l3 != result2.l3
    end
  end

  describe "build_measurement/1" do
    test "builds comprehensive measurement map" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home-123",
        battery_percent: 75.0,
        source: "solar",
        city: "Test City",
        postal_code: "1000",
        region: "flanders"
      ]

      result = Measurement.build_measurement(opts)

      assert is_map(result)
      assert result["home_id"] == "test-home-123"
      assert result["city"] == "Test City"
      assert result["postal_code"] == "1000"
      assert result["region"] == "flanders"
      assert result["source"] == "solar"
      assert result["battery_percent"] == 75.0
    end

    test "includes all power measurements" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      assert result["power_w"] == 3000.0
      assert result["power_l1_w"] == 1000.0
      assert result["power_l2_w"] == 1000.0
      assert result["power_l3_w"] == 1000.0
    end

    test "includes all voltage measurements" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 229.5, l2: 230.2, l3: 230.8, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      assert result["voltage_v"] == 230.0
      assert result["voltage_l1_v"] == 229.5
      assert result["voltage_l2_v"] == 230.2
      assert result["voltage_l3_v"] == 230.8
    end

    test "calculates current from power and voltage" do
      power_distribution = %{l1: 2300.0, l2: 2300.0, l3: 2300.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      # Total current should be 30A (6900W / 230V)
      assert result["current_a"] == 30.0
      assert result["current_l1_a"] == 10.0
      assert result["current_l2_a"] == 10.0
      assert result["current_l3_a"] == 10.0
    end

    test "includes timestamp in ISO8601 format" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      assert is_binary(result["timestamp"])
      # Should be parseable as DateTime
      assert {:ok, _dt, _} = DateTime.from_iso8601(result["timestamp"])
    end

    test "includes grid frequency" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      assert is_float(result["frequency_hz"])
      assert result["frequency_hz"] >= 49.8 and result["frequency_hz"] <= 50.2
    end

    test "uses default values for optional parameters" do
      power_distribution = %{l1: 1000.0, l2: 1000.0, l3: 1000.0}
      voltage = %{l1: 230.0, l2: 230.0, l3: 230.0, total: 230.0}

      opts = [
        power_distribution: power_distribution,
        voltage: voltage,
        home_id: "test-home",
        battery_percent: 50.0
      ]

      result = Measurement.build_measurement(opts)

      # Default values should be used
      assert result["source"] == "grid"
      assert result["city"] == "Unknown"
      assert result["postal_code"] == "0000"
      assert result["region"] == "unknown"
    end
  end
end
