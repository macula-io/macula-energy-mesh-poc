defmodule CortexIqCore.TimestampSerializationTest do
  @moduledoc """
  Integration tests to ensure all domain models serialize timestamps with
  microsecond precision for database compatibility.

  This test suite prevents regressions of the timestamp precision bug where
  DateTime.to_iso8601/1 was producing 3-digit millisecond precision instead
  of the required 6-digit microsecond precision for PostgreSQL :utc_datetime_usec.
  """
  use ExUnit.Case, async: true

  alias CortexIqCore.{
    EnergyBalance,
    ContractOffer,
    SpotPrice,
    DateTimeHelpers
  }

  describe "EnergyBalance.to_event/2" do
    test "serializes all timestamps with microsecond precision" do
      simulation_time = ~U[2025-06-15 14:32:00.123456Z]
      period_start = ~U[2025-01-01 00:00:00.000000Z]

      balance = EnergyBalance.new("home_001", "contract_123", period_start)
      |> EnergyBalance.record_buy(10.5, 0.15, simulation_time)

      event = EnergyBalance.to_event(balance, simulation_time)

      # Verify all timestamp fields have microsecond precision
      assert DateTimeHelpers.has_microsecond_precision?(event.period_start)
      assert DateTimeHelpers.has_microsecond_precision?(event.period_end)
      assert DateTimeHelpers.has_microsecond_precision?(event.simulation_time)

      # Verify specific format
      assert event.period_start == "2025-01-01T00:00:00.000000Z"
      assert event.simulation_time == "2025-06-15T14:32:00.123456Z"
    end
  end

  describe "ContractOffer.to_event/2 - Static" do
    test "serializes all timestamps with microsecond precision" do
      simulation_time = ~U[2025-06-15 14:32:00.123456Z]
      valid_from = ~U[2025-06-15 00:00:00.000000Z]

      pricing = %{
        day_buy_price: 0.15,
        night_buy_price: 0.08,
        day_sell_price: 0.10,
        night_sell_price: 0.05,
        switching_discount: 25.0,
        minimum_monthly_kwh: 100.0
      }

      offer = ContractOffer.new_static("provider_a", pricing, valid_from)
      event = ContractOffer.to_event(offer, simulation_time)

      # Verify timestamp precision
      assert DateTimeHelpers.has_microsecond_precision?(event.valid_from)
      assert DateTimeHelpers.has_microsecond_precision?(event.simulation_time)

      assert event.valid_from == "2025-06-15T00:00:00.000000Z"
      assert event.simulation_time == "2025-06-15T14:32:00.123456Z"
    end
  end

  describe "ContractOffer.to_event/2 - Dynamic" do
    test "serializes all timestamps with microsecond precision" do
      simulation_time = ~U[2025-06-15 14:32:00.123456Z]
      valid_from = ~U[2025-06-15 00:00:00.000000Z]

      pricing = %{
        buy_markup: 0.02,
        sell_markdown: 0.01,
        switching_discount: 30.0,
        minimum_monthly_kwh: 150.0
      }

      offer = ContractOffer.new_dynamic("provider_b", pricing, valid_from)
      event = ContractOffer.to_event(offer, simulation_time)

      # Verify timestamp precision
      assert DateTimeHelpers.has_microsecond_precision?(event.valid_from)
      assert DateTimeHelpers.has_microsecond_precision?(event.simulation_time)

      assert event.valid_from == "2025-06-15T00:00:00.000000Z"
      assert event.simulation_time == "2025-06-15T14:32:00.123456Z"
    end
  end

  describe "SpotPrice.to_event/2" do
    test "serializes all timestamps with microsecond precision" do
      simulation_time = ~U[2025-06-15 14:32:00.123456Z]
      valid_from = ~U[2025-06-15 14:00:00.000000Z]

      spot_price = SpotPrice.new("provider_a", 0.18, 0.09, valid_from)
      event = SpotPrice.to_event(spot_price, simulation_time)

      # Verify timestamp precision
      assert DateTimeHelpers.has_microsecond_precision?(event.valid_from)
      assert DateTimeHelpers.has_microsecond_precision?(event.simulation_time)

      assert event.valid_from == "2025-06-15T14:00:00.000000Z"
      assert event.simulation_time == "2025-06-15T14:32:00.123456Z"
    end
  end

  describe "regression prevention" do
    test "timestamps created from DateTime.add (simulation clock pattern) are correct" do
      # This was the source of the original bug - DateTime.add returns
      # millisecond precision, but we need microsecond precision for Ecto
      base_time = ~U[2025-01-01 00:00:00.000000Z]
      simulation_time = DateTime.add(base_time, 86_400_000, :millisecond)  # 1 day

      balance = EnergyBalance.new("home_001", "contract_123", base_time)
      event = EnergyBalance.to_event(balance, simulation_time)

      # This would fail with old code:
      # DateTime.to_iso8601(simulation_time) -> "2025-01-02T00:00:00.000Z" (3 digits)
      # DateTimeHelpers.to_iso8601(simulation_time) -> "2025-01-02T00:00:00.000000Z" (6 digits)
      assert DateTimeHelpers.has_microsecond_precision?(event.simulation_time)
    end

    test "all timestamp fields in complex event maintain precision" do
      # Create scenario with multiple timestamp fields
      simulation_time = DateTime.add(~U[2025-01-01 00:00:00Z], 1_234_567, :millisecond)
      period_start = DateTime.add(~U[2025-01-01 00:00:00Z], 100_000, :millisecond)

      balance = EnergyBalance.new("home_001", "contract_123", period_start)
      |> EnergyBalance.record_buy(10.0, 0.15, simulation_time)
      |> EnergyBalance.record_sell(5.0, 0.10, simulation_time)

      event = EnergyBalance.to_event(balance, simulation_time)

      # All three timestamp fields must have microsecond precision
      timestamp_fields = [
        event.period_start,
        event.period_end,
        event.simulation_time
      ]

      for timestamp_string <- timestamp_fields do
        assert DateTimeHelpers.has_microsecond_precision?(timestamp_string),
               "Timestamp '#{timestamp_string}' does not have microsecond precision"
      end
    end

    test "event timestamp strings are parseable and database-compatible" do
      # Verify that all event timestamps can be parsed back to DateTime
      simulation_time = ~U[2025-06-15 14:32:00.123456Z]
      valid_from = ~U[2025-06-15 00:00:00.000000Z]

      # Create various event types
      balance = EnergyBalance.new("home_001", nil, valid_from)
      balance_event = EnergyBalance.to_event(balance, simulation_time)

      spot = SpotPrice.new("provider_a", 0.18, 0.09, valid_from)
      spot_event = SpotPrice.to_event(spot, simulation_time)

      pricing = %{day_buy_price: 0.15, night_buy_price: 0.08, day_sell_price: 0.10, night_sell_price: 0.05}
      offer = ContractOffer.new_static("provider_a", pricing, valid_from)
      offer_event = ContractOffer.to_event(offer, simulation_time)

      # Verify all timestamp strings can be parsed and have correct precision
      for {key, value} <- balance_event do
        if is_binary(value) and String.contains?(value, "T") do
          assert DateTimeHelpers.has_microsecond_precision?(value),
                 "Balance event field '#{key}' missing microsecond precision: #{value}"
          {:ok, _dt, _} = DateTimeHelpers.from_iso8601(value)
        end
      end

      for {key, value} <- spot_event do
        if is_binary(value) and String.contains?(value, "T") do
          assert DateTimeHelpers.has_microsecond_precision?(value),
                 "SpotPrice event field '#{key}' missing microsecond precision: #{value}"
        end
      end

      for {key, value} <- offer_event do
        if is_binary(value) and String.contains?(value, "T") do
          assert DateTimeHelpers.has_microsecond_precision?(value),
                 "ContractOffer event field '#{key}' missing microsecond precision: #{value}"
        end
      end
    end
  end
end
