defmodule CortexIqDashboard.Repo.Migrations.AddFinancialTracking do
  use Ecto.Migration

  def change do
    # Add CortexIQ financial tracking fields to home_states
    alter table(:home_states) do
      add :cortexiq_total_commission, :float, default: 0.0
      add :cortexiq_total_savings, :float, default: 0.0
      add :cortexiq_net_savings, :float, default: 0.0
      add :contract_switches_count, :integer, default: 0
    end

    # Add CortexIQ financial tracking fields to system_stats
    alter table(:system_stats) do
      add :cortexiq_total_commission, :float, default: 0.0
      add :cortexiq_total_savings, :float, default: 0.0
      add :cortexiq_net_savings, :float, default: 0.0
    end

    # Create contract_switches table for tracking individual switches
    create table(:contract_switches, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :home_id, :string, null: false
      add :home_name, :string

      # Contract switch details
      add :from_provider_id, :string, null: false
      add :to_provider_id, :string, null: false
      add :from_contract_id, :string
      add :to_contract_id, :string

      # Financial details
      add :gross_savings, :float, null: false
      add :cortexiq_commission, :float, null: false
      add :net_savings_to_customer, :float, null: false
      add :commission_rate, :float, default: 0.20

      # Cumulative totals at time of switch
      add :cumulative_commission, :float, default: 0.0
      add :cumulative_gross_savings, :float, default: 0.0
      add :cumulative_net_savings, :float, default: 0.0
      add :total_switches, :integer, default: 1

      # Timing
      add :simulation_time, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:contract_switches, [:home_id])
    create index(:contract_switches, [:from_provider_id])
    create index(:contract_switches, [:to_provider_id])
    create index(:contract_switches, [:simulation_time])
  end
end
