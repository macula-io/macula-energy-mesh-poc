defmodule CortexIqDashboardSchemas.Repo.Migrations.AddLocationAndCapacityFieldsToHomeStates do
  use Ecto.Migration

  def change do
    alter table(:home_states) do
      add :street, :string
      add :latitude, :float
      add :longitude, :float
      add :solar_capacity_kw, :float
    end
  end
end
