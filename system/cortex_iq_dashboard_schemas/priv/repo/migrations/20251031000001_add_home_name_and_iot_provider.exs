defmodule CortexIqDashboardSchemas.Repo.Migrations.AddHomeNameAndIotProvider do
  use Ecto.Migration

  def change do
    alter table(:home_states) do
      add :name, :string
      add :iot_provider, :string
    end

    # Add index for filtering by IoT provider
    create index(:home_states, [:iot_provider])
  end
end
