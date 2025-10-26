defmodule CortexIqDashboardSchemas.TimeSeries.EnergyTrade do
  @moduledoc """
  Ecto schema for hourly energy trades (grid import/export with costs).
  Stored in TimescaleDB hypertable partitioned by simulation_time.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :id, autogenerate: true}
  schema "energy_trades" do
    field :home_id, :string
    field :provider_id, :string
    field :contract_id, :string
    field :simulation_time, :utc_datetime_usec
    field :simulation_hour, :integer
    field :grid_import_kwh, :float
    field :grid_export_kwh, :float
    field :import_price_per_kwh, :float
    field :export_price_per_kwh, :float
    field :is_day, :boolean
    field :import_cost, :float
    field :export_revenue, :float
    field :net_cost, :float
    field :recorded_at, :utc_datetime_usec
  end

  def changeset(trade, attrs) do
    trade
    |> cast(attrs, [
      :home_id,
      :provider_id,
      :contract_id,
      :simulation_time,
      :simulation_hour,
      :grid_import_kwh,
      :grid_export_kwh,
      :import_price_per_kwh,
      :export_price_per_kwh,
      :is_day,
      :import_cost,
      :export_revenue,
      :net_cost,
      :recorded_at
    ])
    |> validate_required([
      :home_id,
      :provider_id,
      :simulation_time,
      :simulation_hour,
      :is_day,
      :recorded_at
    ])
  end

  def from_wamp_event(event_data) do
    %{
      home_id: event_data["home_id"],
      provider_id: event_data["provider_id"],
      contract_id: event_data["contract_id"],
      simulation_time: parse_datetime(event_data["simulation_time"]),
      simulation_hour: event_data["simulation_hour"],
      grid_import_kwh: event_data["grid_import_kwh"] || 0.0,
      grid_export_kwh: event_data["grid_export_kwh"] || 0.0,
      import_price_per_kwh: event_data["import_price_per_kwh"],
      export_price_per_kwh: event_data["export_price_per_kwh"],
      is_day: event_data["is_day"],
      import_cost: event_data["import_cost"] || 0.0,
      export_revenue: event_data["export_revenue"] || 0.0,
      net_cost: event_data["net_cost"] || 0.0,
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
