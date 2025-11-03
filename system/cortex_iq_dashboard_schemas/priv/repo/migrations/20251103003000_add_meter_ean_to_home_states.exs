defmodule CortexIqDashboardSchemas.Repo.Migrations.AddMeterEanToHomeStates do
  use Ecto.Migration

  def change do
    alter table(:home_states) do
      add :meter_ean, :string, null: false
    end

    # Add unique index for meter_ean (each meter should be unique)
    create unique_index(:home_states, [:meter_ean])
  end
end
