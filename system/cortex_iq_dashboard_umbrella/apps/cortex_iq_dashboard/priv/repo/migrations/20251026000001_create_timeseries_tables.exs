defmodule CortexIqDashboard.Repo.Migrations.CreateTimeseriesTables do
  use Ecto.Migration

  def up do
    # Enable TimescaleDB extension
    execute "CREATE EXTENSION IF NOT EXISTS timescaledb CASCADE"

    # Energy events (high-resolution time-series data)
    # TimescaleDB requires partitioning column to be part of primary key
    create table(:energy_events, primary_key: false) do
      add :home_id, :string, null: false
      add :simulation_time, :utc_datetime_usec, null: false

      # Energy metrics
      add :production_watts, :float, default: 0.0
      add :consumption_watts, :float, default: 0.0
      add :battery_percent, :float, default: 0.0
      add :battery_kwh, :float, default: 0.0
      add :battery_state, :string  # :charging, :discharging, :idle

      # Real timestamp when event was recorded
      add :recorded_at, :utc_datetime_usec, null: false
    end

    # Add composite primary key including partitioning column
    execute """
    ALTER TABLE energy_events ADD PRIMARY KEY (home_id, simulation_time)
    """

    # Convert to hypertable (partitioned by simulation_time with 1-hour chunks)
    execute """
    SELECT create_hypertable(
      'energy_events',
      'simulation_time',
      chunk_time_interval => INTERVAL '1 hour',
      if_not_exists => TRUE
    )
    """

    # Indexes for efficient queries
    create index(:energy_events, [:home_id, :simulation_time])
    create index(:energy_events, [:simulation_time])

    # Energy trades (hourly aggregated buy/sell transactions)
    # TimescaleDB requires partitioning column to be part of primary key
    create table(:energy_trades, primary_key: false) do
      add :home_id, :string, null: false
      add :provider_id, :string, null: false
      add :contract_id, :string
      add :simulation_time, :utc_datetime_usec, null: false
      add :simulation_hour, :integer, null: false

      # Import/Export amounts
      add :grid_import_kwh, :float, default: 0.0  # Energy bought from provider
      add :grid_export_kwh, :float, default: 0.0  # Energy sold to provider

      # Pricing
      add :import_price_per_kwh, :float
      add :export_price_per_kwh, :float
      add :is_day, :boolean, null: false  # Day rate (6am-6pm) vs night rate

      # Financial totals
      add :import_cost, :float, default: 0.0
      add :export_revenue, :float, default: 0.0
      add :net_cost, :float, default: 0.0  # import_cost - export_revenue

      # Real timestamp when trade was recorded
      add :recorded_at, :utc_datetime_usec, null: false
    end

    # Add composite primary key including partitioning column
    execute """
    ALTER TABLE energy_trades ADD PRIMARY KEY (home_id, simulation_time)
    """

    # Convert to hypertable (partitioned by simulation_time with 1-day chunks)
    execute """
    SELECT create_hypertable(
      'energy_trades',
      'simulation_time',
      chunk_time_interval => INTERVAL '1 day',
      if_not_exists => TRUE
    )
    """

    # Indexes for efficient queries
    create index(:energy_trades, [:home_id, :simulation_time])
    create index(:energy_trades, [:provider_id, :simulation_time])
    create index(:energy_trades, [:contract_id])
    create index(:energy_trades, [:simulation_time])

    # Contract events (lifecycle: signed, switched, expired)
    create table(:contract_events) do
      add :contract_id, :string, null: false
      add :home_id, :string, null: false
      add :provider_id, :string, null: false
      add :event_type, :string, null: false  # :signed, :switched, :expired
      add :simulation_time, :utc_datetime_usec, null: false

      # Contract details
      add :start_date, :utc_datetime_usec
      add :end_date, :utc_datetime_usec
      add :day_buy_price, :float
      add :night_buy_price, :float
      add :day_sell_price, :float
      add :night_sell_price, :float
      add :switching_discount, :float

      # Switch metadata (only for event_type = :switched)
      add :previous_contract_id, :string
      add :previous_provider_id, :string
      add :switch_reason, :string
      add :projected_savings, :float
      add :days_before_expiry, :integer

      timestamps(type: :utc_datetime_usec)
    end

    create index(:contract_events, [:home_id, :simulation_time])
    create index(:contract_events, [:provider_id, :simulation_time])
    create index(:contract_events, [:contract_id])
    create index(:contract_events, [:event_type])

    # Create continuous aggregates for dashboard queries
    # Hourly energy production/consumption per home
    execute """
    CREATE MATERIALIZED VIEW energy_hourly_agg
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('1 hour', simulation_time) AS hour,
      home_id,
      AVG(production_watts) as avg_production_watts,
      AVG(consumption_watts) as avg_consumption_watts,
      AVG(battery_percent) as avg_battery_percent,
      MAX(production_watts) as max_production_watts,
      MAX(consumption_watts) as max_consumption_watts,
      COUNT(*) as event_count
    FROM energy_events
    GROUP BY hour, home_id
    WITH NO DATA
    """

    # Set up refresh policy (refresh hourly aggregates every 5 minutes)
    execute """
    SELECT add_continuous_aggregate_policy('energy_hourly_agg',
      start_offset => INTERVAL '1 day',
      end_offset => INTERVAL '1 hour',
      schedule_interval => INTERVAL '5 minutes',
      if_not_exists => TRUE
    )
    """

    # Daily trade summary per home
    execute """
    CREATE MATERIALIZED VIEW trades_daily_agg
    WITH (timescaledb.continuous) AS
    SELECT
      time_bucket('1 day', simulation_time) AS day,
      home_id,
      provider_id,
      SUM(grid_import_kwh) as total_import_kwh,
      SUM(grid_export_kwh) as total_export_kwh,
      SUM(import_cost) as total_import_cost,
      SUM(export_revenue) as total_export_revenue,
      SUM(net_cost) as total_net_cost,
      COUNT(*) as trade_count
    FROM energy_trades
    GROUP BY day, home_id, provider_id
    WITH NO DATA
    """

    # Set up refresh policy for daily trade aggregates
    execute """
    SELECT add_continuous_aggregate_policy('trades_daily_agg',
      start_offset => INTERVAL '7 days',
      end_offset => INTERVAL '1 day',
      schedule_interval => INTERVAL '1 hour',
      if_not_exists => TRUE
    )
    """
  end

  def down do
    # Drop continuous aggregates first
    execute "DROP MATERIALIZED VIEW IF EXISTS trades_daily_agg CASCADE"
    execute "DROP MATERIALIZED VIEW IF EXISTS energy_hourly_agg CASCADE"

    # Drop tables (hypertables are dropped like regular tables)
    drop table(:contract_events)
    drop table(:energy_trades)
    drop table(:energy_events)

    # Note: We don't drop the extension as other objects might depend on it
  end
end
