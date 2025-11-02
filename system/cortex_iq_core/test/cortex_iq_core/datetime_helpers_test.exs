defmodule CortexIqCore.DateTimeHelpersTest do
  use ExUnit.Case, async: true
  alias CortexIqCore.DateTimeHelpers

  doctest CortexIqCore.DateTimeHelpers

  describe "to_iso8601/1" do
    test "converts DateTime to ISO8601 string with microsecond precision" do
      dt = ~U[2025-06-15 14:32:00.123456Z]
      result = DateTimeHelpers.to_iso8601(dt)

      assert result == "2025-06-15T14:32:00.123456Z"
      assert DateTimeHelpers.has_microsecond_precision?(result)
    end

    test "handles DateTime with millisecond precision by padding zeros" do
      # Create DateTime with millisecond precision (3 digits)
      {:ok, dt, _} = DateTime.from_iso8601("2025-06-15T14:32:00.123Z")
      result = DateTimeHelpers.to_iso8601(dt)

      # Should pad to 6 digits
      assert result == "2025-06-15T14:32:00.123000Z"
      assert DateTimeHelpers.has_microsecond_precision?(result)
    end

    test "handles DateTime with no fractional seconds" do
      dt = ~U[2025-06-15 14:32:00Z]
      result = DateTimeHelpers.to_iso8601(dt)

      # Should add .000000
      assert result == "2025-06-15T14:32:00.000000Z"
      assert DateTimeHelpers.has_microsecond_precision?(result)
    end

    test "handles DateTime created from DateTime.add/3" do
      # Simulate simulation clock behavior
      base = ~U[2025-01-01 00:00:00Z]
      dt = DateTime.add(base, 1000, :millisecond)
      result = DateTimeHelpers.to_iso8601(dt)

      # Should have 6-digit precision
      assert String.match?(result, ~r/\.\d{6}Z$/)
      assert DateTimeHelpers.has_microsecond_precision?(result)
    end
  end

  describe "from_iso8601/1" do
    test "parses valid ISO8601 string with microsecond precision" do
      {:ok, dt, offset} = DateTimeHelpers.from_iso8601("2025-06-15T14:32:00.123456Z")

      assert dt == ~U[2025-06-15 14:32:00.123456Z]
      assert offset == 0
    end

    test "parses valid ISO8601 string with millisecond precision" do
      {:ok, dt, offset} = DateTimeHelpers.from_iso8601("2025-06-15T14:32:00.123Z")

      assert dt == ~U[2025-06-15 14:32:00.123Z]
      assert offset == 0
    end

    test "returns error for invalid format" do
      assert {:error, :invalid_format} == DateTimeHelpers.from_iso8601("not a datetime")
    end
  end

  describe "has_microsecond_precision?/1" do
    test "returns true for strings with 6-digit fractional seconds" do
      assert DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.123456Z")
      assert DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.000000Z")
      assert DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.999999Z")
    end

    test "returns false for strings with 3-digit fractional seconds" do
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.123Z")
    end

    test "returns false for strings with no fractional seconds" do
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00Z")
    end

    test "returns false for strings with other digit counts" do
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.1Z")
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.12Z")
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.1234Z")
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.12345Z")
      refute DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.1234567Z")
    end
  end

  describe "round-trip conversion" do
    test "DateTime -> ISO8601 -> DateTime preserves value" do
      original = ~U[2025-06-15 14:32:00.123456Z]

      iso_string = DateTimeHelpers.to_iso8601(original)
      {:ok, parsed, _} = DateTimeHelpers.from_iso8601(iso_string)

      assert DateTime.compare(original, parsed) == :eq
    end

    test "works with simulation time values" do
      # Simulate typical simulation clock pattern
      base = ~U[2025-01-01 00:00:00.000000Z]
      elapsed_ms = 105_120_000  # 1 simulated day at 105,120x speed
      simulated = DateTime.add(base, elapsed_ms, :millisecond)

      iso_string = DateTimeHelpers.to_iso8601(simulated)
      {:ok, parsed, _} = DateTimeHelpers.from_iso8601(iso_string)

      assert DateTimeHelpers.has_microsecond_precision?(iso_string)
      assert DateTime.compare(simulated, parsed) == :eq
    end
  end

  describe "Ecto compatibility" do
    test "output is compatible with :utc_datetime_usec field type" do
      # This would be validated by Ecto's EnergyEvent.ensure_microsecond_precision/1
      dt = ~U[2025-06-15 14:32:00.123456Z]
      iso_string = DateTimeHelpers.to_iso8601(dt)

      # Ecto expects exactly 6 digits of fractional seconds
      assert Regex.match?(~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{6}Z$/, iso_string)
    end

    test "all timestamps from typical events have correct precision" do
      # Simulate different timestamp sources
      timestamps = [
        ~U[2025-06-15 14:32:00.123456Z],  # Already has microseconds
        ~U[2025-06-15 14:32:00.123Z],     # Milliseconds only
        ~U[2025-06-15 14:32:00Z],         # No fractional seconds
        DateTime.utc_now(),                # Current time
        DateTime.add(~U[2025-01-01 00:00:00Z], 1000, :millisecond)  # Simulated time
      ]

      for timestamp <- timestamps do
        iso_string = DateTimeHelpers.to_iso8601(timestamp)
        assert DateTimeHelpers.has_microsecond_precision?(iso_string),
               "Failed for timestamp: #{inspect(timestamp)}, got: #{iso_string}"
      end
    end
  end
end
