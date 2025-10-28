defmodule CortexIqDashboardSchemas.Repo.Migrations.AddHomeConnectionTracking do
  use Ecto.Migration

  def change do
    alter table(:home_states) do
      add :connected_at, :utc_datetime_usec
      add :disconnected_at, :utc_datetime_usec
    end

    # Add index for connection status queries
    create index(:home_states, [:connected_at])
    create index(:home_states, [:disconnected_at])
  end
end
