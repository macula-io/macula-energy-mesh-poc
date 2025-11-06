defmodule CortexIqDashboardSchemas.MetricsTimeseries do
  @moduledoc """
  Time-series storage for system performance and health metrics.

  Metrics are calculated by cortex_iq_projections service and stored here
  for historical analysis and charting.

  Metrics include:
  - Performance: events/sec, measurements/sec, meter readings/sec
  - System health: homes online, connected, total
  - Energy: production, consumption, battery state
  - Market: active contracts, switches

  Published on: macula.metrics.totals_calculated
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "metrics_timeseries" do
    field :timestamp, :utc_datetime_usec
    field :simulation_time, :utc_datetime_usec

    # Performance metrics
    field :events_per_second, :float, default: 0.0
    field :measurements_per_second, :float, default: 0.0
    field :meter_readings_per_second, :float, default: 0.0

    # System health metrics
    field :homes_online, :integer, default: 0
    field :homes_total, :integer, default: 0
    field :homes_connected, :integer, default: 0

    # Energy metrics
    field :total_production_kw, :float, default: 0.0
    field :total_consumption_kw, :float, default: 0.0
    field :total_battery_kwh, :float, default: 0.0
    field :total_battery_capacity_kwh, :float, default: 0.0
    field :avg_battery_soc_pct, :float, default: 0.0

    # Market metrics
    field :active_contracts, :integer, default: 0
    field :contract_switches_last_minute, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(metrics, attrs) do
    metrics
    |> cast(attrs, [
      :timestamp,
      :simulation_time,
      # Performance
      :events_per_second,
      :measurements_per_second,
      :meter_readings_per_second,
      # System health
      :homes_online,
      :homes_total,
      :homes_connected,
      # Energy
      :total_production_kw,
      :total_consumption_kw,
      :total_battery_kwh,
      :total_battery_capacity_kwh,
      :avg_battery_soc_pct,
      # Market
      :active_contracts,
      :contract_switches_last_minute
    ])
    |> validate_required([:timestamp])
  end
end
