defmodule CortexIqDashboardSchemas.Repo.Migrations.AddSpotPricesToProviderStates do
  use Ecto.Migration

  def change do
    alter table(:provider_states) do
      add :spot_buy_price, :float
      add :spot_sell_price, :float
    end
  end
end
