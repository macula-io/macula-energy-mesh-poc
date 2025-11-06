defmodule CortexIqDashboardSchemas.Repo.Migrations.ReplaceMeterEanWithMultiMeterFields do
  use Ecto.Migration

  def up do
    alter table(:home_states) do
      # Remove old single meter_ean field
      remove :meter_ean

      # Add multiple meter EAN fields (18-digit format)
      add :electricity_day_meter_ean, :string       # Day tariff (6am-10pm)
      add :electricity_night_meter_ean, :string     # Night tariff (10pm-6am)
      add :electricity_single_meter_ean, :string    # Single-rate alternative
      add :gas_meter_ean, :string                   # Gas meter (optional)
      add :water_meter_ean, :string                 # Water meter (optional)

      # Add cumulative meter readings
      add :electricity_day_cumulative_kwh, :float, default: 0.0
      add :electricity_night_cumulative_kwh, :float, default: 0.0
      add :gas_cumulative_m3, :float, default: 0.0
      add :water_cumulative_m3, :float, default: 0.0
    end

    # Add indices for meter EAN lookups (for search/verification)
    create index(:home_states, [:electricity_day_meter_ean])
    create index(:home_states, [:electricity_night_meter_ean])
    create index(:home_states, [:gas_meter_ean])
    create index(:home_states, [:water_meter_ean])
  end

  def down do
    alter table(:home_states) do
      # Remove multi-meter fields
      remove :electricity_day_meter_ean
      remove :electricity_night_meter_ean
      remove :electricity_single_meter_ean
      remove :gas_meter_ean
      remove :water_meter_ean

      remove :electricity_day_cumulative_kwh
      remove :electricity_night_cumulative_kwh
      remove :gas_cumulative_m3
      remove :water_cumulative_m3

      # Restore original meter_ean field
      add :meter_ean, :string
    end

    # Drop indices
    drop index(:home_states, [:electricity_day_meter_ean])
    drop index(:home_states, [:electricity_night_meter_ean])
    drop index(:home_states, [:gas_meter_ean])
    drop index(:home_states, [:water_meter_ean])
  end
end
