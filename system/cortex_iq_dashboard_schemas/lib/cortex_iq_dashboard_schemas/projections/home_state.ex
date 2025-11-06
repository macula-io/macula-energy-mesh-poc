defmodule CortexIqDashboardSchemas.Projections.HomeState do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:home_id, :string, autogenerate: false}
  schema "home_states" do
    field :name, :string
    field :iot_provider, :string

    # Multiple meter EAN numbers (18-digit format)
    field :electricity_day_meter_ean, :string    # Day tariff meter (6am-10pm)
    field :electricity_night_meter_ean, :string  # Night tariff meter (10pm-6am)
    field :electricity_single_meter_ean, :string # Single-rate meter (alternative)
    field :gas_meter_ean, :string                # Gas meter (optional, ~70% homes)
    field :water_meter_ean, :string              # Water meter (optional, ~80% homes)

    # Cumulative meter readings
    field :electricity_day_cumulative_kwh, :float, default: 0.0
    field :electricity_night_cumulative_kwh, :float, default: 0.0
    field :gas_cumulative_m3, :float, default: 0.0
    field :water_cumulative_m3, :float, default: 0.0

    field :location, :string
    field :postal_code, :string
    field :region, :string
    field :street, :string
    field :latitude, :float
    field :longitude, :float

    field :solar_capacity_kw, :float
    field :production_kw, :float
    field :consumption_kw, :float
    field :battery_percent, :float
    field :battery_kwh, :float
    field :battery_capacity_kwh, :float

    field :provider_id, :string
    field :contract_id, :string
    field :contract_expires_at, :utc_datetime_usec

    field :energy_bought_kwh, :float
    field :energy_sold_kwh, :float
    field :net_balance_kwh, :float
    field :cost_paid, :float
    field :revenue_received, :float
    field :net_cost, :float

    # CortexIQ financial tracking
    field :cortexiq_total_commission, :float
    field :cortexiq_total_savings, :float
    field :cortexiq_net_savings, :float
    field :contract_switches_count, :integer

    field :last_event_at, :utc_datetime_usec

    # Connection tracking
    field :connected_at, :utc_datetime_usec
    field :disconnected_at, :utc_datetime_usec

    # Status (BitFlags) - See CortexIqDashboardSchemas.HomeStatus
    field :status, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(home_state, attrs) do
    home_state
    |> cast(attrs, [
      :home_id,
      :name,
      :iot_provider,
      # Multiple meter EANs
      :electricity_day_meter_ean,
      :electricity_night_meter_ean,
      :electricity_single_meter_ean,
      :gas_meter_ean,
      :water_meter_ean,
      # Cumulative readings
      :electricity_day_cumulative_kwh,
      :electricity_night_cumulative_kwh,
      :gas_cumulative_m3,
      :water_cumulative_m3,
      :location,
      :postal_code,
      :region,
      :street,
      :latitude,
      :longitude,
      :solar_capacity_kw,
      :production_kw,
      :consumption_kw,
      :battery_percent,
      :battery_kwh,
      :battery_capacity_kwh,
      :provider_id,
      :contract_id,
      :contract_expires_at,
      :energy_bought_kwh,
      :energy_sold_kwh,
      :net_balance_kwh,
      :cost_paid,
      :revenue_received,
      :net_cost,
      :cortexiq_total_commission,
      :cortexiq_total_savings,
      :cortexiq_net_savings,
      :contract_switches_count,
      :last_event_at,
      :connected_at,
      :disconnected_at,
      :status
    ])
    |> validate_required([:home_id, :status])
  end
end
