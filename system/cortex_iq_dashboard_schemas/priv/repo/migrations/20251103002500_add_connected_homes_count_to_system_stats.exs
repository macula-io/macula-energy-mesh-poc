defmodule CortexIqDashboardSchemas.Repo.Migrations.AddConnectedHomesCountToSystemStats do
  use Ecto.Migration

  def change do
    alter table(:system_stats) do
      # Use IF NOT EXISTS to handle case where column was manually added
      add_if_not_exists :connected_homes_count, :integer, default: 0
    end
  end
end
