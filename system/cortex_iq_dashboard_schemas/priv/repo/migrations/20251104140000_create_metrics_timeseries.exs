defmodule CortexIqDashboardSchemas.Repo.Migrations.CreateMetricsTimeseries do
  use Ecto.Migration

  def up do
    create table(:metrics_timeseries, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :timestamp, :utc_datetime_usec, null: false
      add :simulation_time, :utc_datetime_usec

      # Performance metrics
      add :events_per_second, :float, default: 0.0
      add :measurements_per_second, :float, default: 0.0
      add :meter_readings_per_second, :float, default: 0.0

      # System health metrics
      add :homes_online, :integer, default: 0
      add :homes_total, :integer, default: 0
      add :homes_connected, :integer, default: 0

      # Energy metrics
      add :total_production_kw, :float, default: 0.0
      add :total_consumption_kw, :float, default: 0.0
      add :total_battery_kwh, :float, default: 0.0
      add :total_battery_capacity_kwh, :float, default: 0.0
      add :avg_battery_soc_pct, :float, default: 0.0

      # Market metrics
      add :active_contracts, :integer, default: 0
      add :contract_switches_last_minute, :integer, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    # Index for time-series queries
    create index(:metrics_timeseries, [:timestamp])
    create index(:metrics_timeseries, [:simulation_time])

    # Index for latest metrics query
    create index(:metrics_timeseries, [:inserted_at])
  end

  def down do
    drop table(:metrics_timeseries)
  end
end
