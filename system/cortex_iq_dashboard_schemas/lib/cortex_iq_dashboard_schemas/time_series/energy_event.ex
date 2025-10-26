defmodule CortexIqDashboardSchemas.TimeSeries.EnergyEvent do
  @moduledoc """
  Ecto schema for high-resolution energy events (production, consumption, battery).
  Stored in TimescaleDB hypertable partitioned by simulation_time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "energy_events" do
    field :home_id, :string
    field :simulation_time, :utc_datetime_usec
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
      simulation_time: parse_datetime(event_data["simulation_time"]),
      production_watts: event_data["production_watts"],
      consumption_watts: event_data["consumption_watts"],
      battery_percent: event_data["battery_percent"],
      battery_kwh: event_data["battery_kwh"],
      battery_state: event_data["battery_state"],
      recorded_at: DateTime.utc_now()
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(iso8601_string) when is_binary(iso8601_string) do
    case DateTime.from_iso8601(iso8601_string) do
      {:ok, datetime, _} -> datetime
      _ -> nil
    end
  end

  defp parse_datetime(datetime), do: datetime
end
