defmodule CortexIqDashboardSchemas.Projections.ProviderState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:provider_id, :string, autogenerate: false}
  schema "provider_states" do
    field :provider_name, :string
    field :strategy, :string

    field :active_contracts, :integer
    field :market_share_percent, :float

    field :day_buy_price, :float
    field :night_buy_price, :float
    field :day_sell_price, :float
    field :night_sell_price, :float
    field :switching_discount, :float

    field :spot_buy_price, :float
    field :spot_sell_price, :float

    field :last_event_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(provider_state, attrs) do
    provider_state
    |> cast(attrs, [
      :provider_id,
      :provider_name,
      :strategy,
      :active_contracts,
      :market_share_percent,
      :day_buy_price,
      :night_buy_price,
      :day_sell_price,
      :night_sell_price,
      :switching_discount,
      :spot_buy_price,
      :spot_sell_price,
      :last_event_at
    ])
    |> validate_required([:provider_id])
  end
end
