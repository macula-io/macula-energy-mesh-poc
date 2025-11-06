defmodule CortexIqDashboardSchemas.Repo.Migrations.AddFinancialAndActivityMetricsToProviderStates do
  use Ecto.Migration

  def change do
    alter table(:provider_states) do
      # Market position metrics
      add :rank, :integer
      add :market_share_trend, :string

      # Contract pricing fields
      add :minimum_monthly_kwh, :float

      # Financial metrics (accumulated from home.traded events)
      add :total_revenue, :float, default: 0.0
      add :total_cost, :float, default: 0.0
      add :net_profit, :float, default: 0.0
      add :avg_contract_value, :float, default: 0.0

      # Activity metrics (calculated windows)
      add :contracts_gained_last_minute, :integer, default: 0
      add :contracts_lost_last_minute, :integer, default: 0
      add :net_contract_change, :integer, default: 0

      # Competitive metrics
      add :avg_spread, :float, default: 0.0
      add :price_competitiveness, :string
    end
  end
end
