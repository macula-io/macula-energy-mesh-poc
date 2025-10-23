defmodule CortexIqDashboard.Repo.Migrations.CreateAggregatedStates do
  use Ecto.Migration

  def change do
    # Aggregated home states (updated from WAMP events)
    create table(:home_states, primary_key: false) do
      add :home_id, :string, primary_key: true
      add :location, :string
      add :postal_code, :string
      add :region, :string

      # Current state
      add :production_kw, :float
      add :consumption_kw, :float
      add :battery_percent, :float
      add :battery_kwh, :float
      add :battery_capacity_kwh, :float

      # Contract info
      add :provider_id, :string
      add :contract_id, :string
      add :contract_expires_at, :utc_datetime

      # Energy balance
      add :energy_bought_kwh, :float, default: 0.0
      add :energy_sold_kwh, :float, default: 0.0
      add :net_balance_kwh, :float, default: 0.0
      add :cost_paid, :float, default: 0.0
      add :revenue_received, :float, default: 0.0
      add :net_cost, :float, default: 0.0

      add :last_event_at, :utc_datetime
      timestamps()
    end

    create index(:home_states, [:region])
    create index(:home_states, [:provider_id])

    # Aggregated provider states
    create table(:provider_states, primary_key: false) do
      add :provider_id, :string, primary_key: true
      add :provider_name, :string
      add :strategy, :string

      # Market share
      add :active_contracts, :integer, default: 0
      add :market_share_percent, :float, default: 0.0

      # Latest offer
      add :day_buy_price, :float
      add :night_buy_price, :float
      add :day_sell_price, :float
      add :night_sell_price, :float
      add :switching_discount, :float

      add :last_event_at, :utc_datetime
      timestamps()
    end

    # System-wide statistics
    create table(:system_stats, primary_key: false) do
      add :id, :integer, primary_key: true, default: 1
      add :total_homes, :integer, default: 0
      add :total_providers, :integer, default: 0
      add :total_production_kwh, :float, default: 0.0
      add :total_consumption_kwh, :float, default: 0.0
      add :total_energy_bought_kwh, :float, default: 0.0
      add :total_energy_sold_kwh, :float, default: 0.0
      add :total_cost_paid, :float, default: 0.0
      add :total_revenue_received, :float, default: 0.0
      add :contract_switches_count, :integer, default: 0
      add :avg_battery_percent, :float, default: 0.0

      add :simulation_time, :utc_datetime
      add :simulation_speed, :integer

      timestamps()
    end
  end
end
