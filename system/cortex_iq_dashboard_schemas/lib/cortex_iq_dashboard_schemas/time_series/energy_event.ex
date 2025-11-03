defmodule CortexIqDashboardSchemas.TimeSeries.EnergyEvent do
  @moduledoc """
  Ecto schema for high-resolution energy events (production, consumption, battery).
  Stored in TimescaleDB hypertable partitioned by simulation_time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  schema "energy_events" do
    field :home_id, :string, primary_key: true
    field :simulation_time, :utc_datetime_usec, primary_key: true
    field :production_watts, :float
    field :consumption_watts, :float
    field :battery_percent, :float
    field :battery_kwh, :float
    field :battery_state, :string
    field :recorded_at, :utc_datetime_usec
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :home_id,
      :simulation_time,
      :production_watts,
      :consumption_watts,
      :battery_percent,
      :battery_kwh,
      :battery_state,
      :recorded_at
    ])
    |> validate_required([
      :home_id,
      :simulation_time,
      :recorded_at
    ])
  end

  def from_wamp_event(event_data) do
    %{
      home_id: event_data["home_id"],
      simulation_time: parse_datetime(event_data["timestamp"]),  # Changed from "simulation_time" to "timestamp" for HomeWizard compatibility
      production_watts: event_data["production_watts"],
      consumption_watts: event_data["consumption_watts"],
      battery_percent: event_data["battery_percent"],
      battery_kwh: event_data["battery_kwh"],
      battery_state: event_data["battery_state"],
      recorded_at: ensure_microsecond_precision(DateTime.utc_now())
    }
  end

  defp parse_datetime(nil), do: ensure_microsecond_precision(DateTime.utc_now())  # Prevent NULL constraint violations

  defp parse_datetime(iso8601_string) when is_binary(iso8601_string) do
    case DateTime.from_iso8601(iso8601_string) do
      {:ok, datetime, _} -> ensure_microsecond_precision(datetime)
      _ -> ensure_microsecond_precision(DateTime.utc_now())
    end
  end

  defp parse_datetime(datetime), do: ensure_microsecond_precision(datetime)

  # Convert any DateTime to microsecond precision (6 digits) for :utc_datetime_usec compatibility
  defp ensure_microsecond_precision(%DateTime{} = dt) do
    %{
      year: year,
      month: month,
      day: day,
      hour: hour,
      minute: minute,
      second: second,
      microsecond: {usec, _precision},
      time_zone: tz
    } = dt

    # Rebuild DateTime with explicit microsecond precision (6) using original timezone
    case DateTime.new(
      Date.new!(year, month, day),
      Time.new!(hour, minute, second, {usec, 6}),
      tz
    ) do
      {:ok, new_dt} -> new_dt
      {:error, _} -> dt  # Fallback to original if reconstruction fails
    end
  end
end
