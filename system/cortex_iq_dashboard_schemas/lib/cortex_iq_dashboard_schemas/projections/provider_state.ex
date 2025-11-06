defmodule CortexIqDashboardSchemas.Projections.ProviderState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:provider_id, :string, autogenerate: false}
  schema "provider_states" do
    field :provider_name, :string
    field :strategy, :string

    # Market position
    field :active_contracts, :integer
    field :market_share_percent, :float
    field :rank, :integer  # Ranking by market share (1 = highest)
    field :market_share_trend, :string  # "growing", "stable", "declining"

    # Contract pricing (last offer)
    field :day_buy_price, :float
    field :night_buy_price, :float
    field :day_sell_price, :float
    field :night_sell_price, :float
    field :switching_discount, :float
    field :minimum_monthly_kwh, :float

    # Spot market pricing
    field :spot_buy_price, :float
    field :spot_sell_price, :float

    # Financial metrics (accumulated from home.traded events)
    field :total_revenue, :float  # Total revenue from selling energy to homes
    field :total_cost, :float  # Total cost of buying energy from homes
    field :net_profit, :float  # total_revenue - total_cost
    field :avg_contract_value, :float  # Average revenue per active contract

    # Activity metrics (calculated windows)
    field :contracts_gained_last_minute, :integer  # New contracts in last 60s
    field :contracts_lost_last_minute, :integer  # Lost contracts in last 60s
    field :net_contract_change, :integer  # contracts_gained - contracts_lost

    # Competitive metrics
    field :avg_spread, :float  # Average buy-sell price spread
    field :price_competitiveness, :string  # "cheapest", "competitive", "expensive"

    field :last_event_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(provider_state, attrs) do
    provider_state
    |> cast(attrs, [
      :provider_id,
      :provider_name,
      :strategy,
      # Market position
      :active_contracts,
      :market_share_percent,
      :rank,
      :market_share_trend,
      # Contract pricing
      :day_buy_price,
      :night_buy_price,
      :day_sell_price,
      :night_sell_price,
      :switching_discount,
      :minimum_monthly_kwh,
      # Spot pricing
      :spot_buy_price,
      :spot_sell_price,
      # Financial metrics
      :total_revenue,
      :total_cost,
      :net_profit,
      :avg_contract_value,
      # Activity metrics
      :contracts_gained_last_minute,
      :contracts_lost_last_minute,
      :net_contract_change,
      # Competitive metrics
      :avg_spread,
      :price_competitiveness,
      # Metadata
      :last_event_at
    ])
    |> validate_required([:provider_id])
  end
end
