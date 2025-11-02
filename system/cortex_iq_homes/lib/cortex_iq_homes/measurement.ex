defmodule CortexIqHomes.Measurement do
  @moduledoc """
  Calculations for realistic 3-phase power measurements.

  Inspired by HomeWizard Energy API models, this module provides
  functions to simulate realistic European home electrical measurements.
  """

  @nominal_voltage_v 230.0
  @grid_frequency_hz 50.0
  @voltage_variation_pct 2.0

  @doc """
  Distribute total power across three phases with realistic imbalance.

  European homes have 3-phase power but loads are rarely balanced.
  Returns map with L1, L2, L3 power distribution.
  """
  def distribute_power_across_phases(total_power_w, phase_ratios)
      when is_float(total_power_w) and total_power_w >= 0 do
    %{
      l1: total_power_w * Map.get(phase_ratios, :l1, 0.33),
      l2: total_power_w * Map.get(phase_ratios, :l2, 0.33),
      l3: total_power_w * Map.get(phase_ratios, :l3, 0.34)
    }
  end

  @doc """
  Calculate voltage per phase with small random variations.

  Grid voltage fluctuates slightly (±2%) around nominal 230V.
  """
  def calculate_voltage_per_phase do
    variation = fn ->
      @nominal_voltage_v * (1.0 + (:rand.uniform() - 0.5) * @voltage_variation_pct / 100.0)
    end

    %{
      l1: variation.(),
      l2: variation.(),
      l3: variation.(),
      total: @nominal_voltage_v
    }
  end

  @doc """
  Calculate current from power and voltage (I = P / V).

  Per-phase current is power divided by voltage.
  """
  def calculate_current(power_w, voltage_v)
      when is_float(power_w) and is_float(voltage_v) and voltage_v > 0 do
    power_w / voltage_v
  end

  def calculate_current(_power_w, _voltage_v), do: 0.0

  @doc """
  Get grid frequency with small variations.

  European grid is 50Hz ±0.2Hz typically.
  """
  def calculate_frequency do
    @grid_frequency_hz + (:rand.uniform() - 0.5) * 0.2
  end

  @doc """
  Generate random but realistic phase distribution ratios.

  Ratios sum to 1.0, but with realistic imbalance (one phase usually higher).
  """
  def generate_phase_ratios do
    # Generate 3 random values
    r1 = :rand.uniform()
    r2 = :rand.uniform()
    r3 = :rand.uniform()
    total = r1 + r2 + r3

    %{
      l1: r1 / total,
      l2: r2 / total,
      l3: r3 / total
    }
  end

  @doc """
  Build comprehensive measurement map from individual values.

  Combines all measurements into HomeWizard-style structure.
  """
  def build_measurement(opts) do
    power_distribution = Keyword.fetch!(opts, :power_distribution)
    voltage = Keyword.fetch!(opts, :voltage)
    home_id = Keyword.fetch!(opts, :home_id)
    battery_percent = Keyword.fetch!(opts, :battery_percent)
    source = Keyword.get(opts, :source, "grid")
    city = Keyword.get(opts, :city, "Unknown")
    postal_code = Keyword.get(opts, :postal_code, "0000")
    region = Keyword.get(opts, :region, "unknown")

    total_power = power_distribution.l1 + power_distribution.l2 + power_distribution.l3

    %{
      "home_id" => home_id,
      "city" => city,
      "postal_code" => postal_code,
      "region" => region,
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601(),
      "source" => source,
      # Total power
      "power_w" => Float.round(total_power, 2),
      # Per-phase power
      "power_l1_w" => Float.round(power_distribution.l1, 2),
      "power_l2_w" => Float.round(power_distribution.l2, 2),
      "power_l3_w" => Float.round(power_distribution.l3, 2),
      # Voltage
      "voltage_v" => Float.round(voltage.total, 2),
      "voltage_l1_v" => Float.round(voltage.l1, 2),
      "voltage_l2_v" => Float.round(voltage.l2, 2),
      "voltage_l3_v" => Float.round(voltage.l3, 2),
      # Current (calculated from power/voltage)
      "current_a" => Float.round(calculate_current(total_power, voltage.total), 2),
      "current_l1_a" => Float.round(calculate_current(power_distribution.l1, voltage.l1), 2),
      "current_l2_a" => Float.round(calculate_current(power_distribution.l2, voltage.l2), 2),
      "current_l3_a" => Float.round(calculate_current(power_distribution.l3, voltage.l3), 2),
      # Grid frequency
      "frequency_hz" => Float.round(calculate_frequency(), 2),
      # Battery
      "battery_percent" => Float.round(battery_percent, 2)
    }
  end
end
