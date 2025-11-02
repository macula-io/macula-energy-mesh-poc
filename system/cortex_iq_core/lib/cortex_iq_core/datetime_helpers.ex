defmodule CortexIqCore.DateTimeHelpers do
  @moduledoc """
  Helper functions for DateTime serialization with proper precision handling.

  All timestamps in the CortexIQ system must be serialized with microsecond
  precision (6 digits) to match PostgreSQL `:utc_datetime_usec` field types.

  ## Problem

  Elixir's `DateTime.to_iso8601/1` defaults to millisecond precision (3 digits):
  ```elixir
  DateTime.to_iso8601(~U[2025-06-15 14:32:00.123456Z])
  # Returns: "2025-06-15T14:32:00.123Z"  ← Only 3 digits!
  ```

  This causes Ecto validation errors when inserting into `:utc_datetime_usec` fields:
  ```
  :utc_datetime_usec expects microsecond precision, got: ~U[2025-03-08 23:36:21.600Z]
  ```

  ## Solution

  Always truncate to microseconds before serialization:
  ```elixir
  DateTimeHelpers.to_iso8601(~U[2025-06-15 14:32:00.123456Z])
  # Returns: "2025-06-15T14:32:00.123456Z"  ← 6 digits ✓
  ```

  ## Usage

  Use this module instead of `DateTime.to_iso8601/1` when serializing timestamps
  for WAMP events that will be stored in the database.

  ```elixir
  # Bad - will cause precision errors
  simulation_time: DateTime.to_iso8601(simulation_time)

  # Good - ensures 6-digit microsecond precision
  simulation_time: DateTimeHelpers.to_iso8601(simulation_time)
  ```
  """

  @doc """
  Converts a DateTime to ISO8601 string with microsecond precision (6 digits).

  This function ensures compatibility with PostgreSQL `:utc_datetime_usec` fields
  by always including 6 digits of fractional seconds.

  ## Examples

      iex> dt = ~U[2025-06-15 14:32:00.123456Z]
      iex> DateTimeHelpers.to_iso8601(dt)
      "2025-06-15T14:32:00.123456Z"

      iex> dt = ~U[2025-06-15 14:32:00.1Z]
      iex> DateTimeHelpers.to_iso8601(dt)
      "2025-06-15T14:32:00.100000Z"

  ## Implementation Note

  We use `Calendar.strftime/2` to force 6-digit microsecond output. The default
  `DateTime.to_iso8601/1` uses minimal representation (omits trailing zeros),
  which causes Ecto validation errors for `:utc_datetime_usec` fields.
  """
  @spec to_iso8601(DateTime.t()) :: String.t()
  def to_iso8601(%DateTime{} = datetime) do
    # Ensure microsecond precision
    datetime = DateTime.truncate(datetime, :microsecond)

    # Extract microsecond value and pad to 6 digits
    {microsecond, _precision} = datetime.microsecond
    microsecond_str = microsecond |> Integer.to_string() |> String.pad_leading(6, "0")

    # Format the datetime without fractional seconds, then append our 6-digit microseconds
    base = Calendar.strftime(datetime, "%Y-%m-%dT%H:%M:%S")
    "#{base}.#{microsecond_str}Z"
  end

  @doc """
  Parses an ISO8601 string to a DateTime.

  This is a convenience wrapper around `DateTime.from_iso8601/1` for symmetry
  with `to_iso8601/1`.

  ## Examples

      iex> DateTimeHelpers.from_iso8601("2025-06-15T14:32:00.123456Z")
      {:ok, ~U[2025-06-15 14:32:00.123456Z], 0}

      iex> DateTimeHelpers.from_iso8601("invalid")
      {:error, :invalid_format}
  """
  @spec from_iso8601(String.t()) :: {:ok, DateTime.t(), integer()} | {:error, atom()}
  def from_iso8601(iso8601_string) when is_binary(iso8601_string) do
    DateTime.from_iso8601(iso8601_string)
  end

  @doc """
  Validates that an ISO8601 string has microsecond precision (6 digits).

  Returns `true` if the string has exactly 6 digits of fractional seconds,
  `false` otherwise.

  ## Examples

      iex> DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.123456Z")
      true

      iex> DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00.123Z")
      false

      iex> DateTimeHelpers.has_microsecond_precision?("2025-06-15T14:32:00Z")
      false
  """
  @spec has_microsecond_precision?(String.t()) :: boolean()
  def has_microsecond_precision?(iso8601_string) when is_binary(iso8601_string) do
    # Match pattern: ...\.(\d{6})Z (exactly 6 digits before Z)
    Regex.match?(~r/\.\d{6}Z$/, iso8601_string)
  end
end
