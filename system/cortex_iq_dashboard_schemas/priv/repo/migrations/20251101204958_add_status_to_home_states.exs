defmodule CortexIqDashboardSchemas.Repo.Migrations.AddStatusToHomeStates do
  use Ecto.Migration

  def change do
    alter table(:home_states) do
      # Add status as integer (BitFlags value)
      # Default to 0 (none) for existing records
      # NOT NULL because every home must have a status
      add :status, :integer, default: 0, null: false
    end

    # Add index for efficient status queries
    create index(:home_states, [:status])

    # Add composite index for common queries (status + region, etc.)
    create index(:home_states, [:status, :region])
    create index(:home_states, [:status, :provider_id])
  end
end
