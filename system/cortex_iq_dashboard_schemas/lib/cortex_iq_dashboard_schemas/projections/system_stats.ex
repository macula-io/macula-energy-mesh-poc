defmodule CortexIqDashboardSchemas.Projections.SystemStats do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :integer, autogenerate: false}
  schema "system_stats" do
    field :total_homes, :integer
    field :total_providers, :integer
    field :total_production_kwh, :float
    field :total_consumption_kwh, :float
    field :total_energy_bought_kwh, :float
    field :total_energy_sold_kwh, :float
    field :total_cost_paid, :float
    field :total_revenue_received, :float
    field :contract_switches_count, :integer
    field :avg_battery_percent, :float

    # CortexIQ financial tracking
    field :cortexiq_total_commission, :float
    field :cortexiq_total_savings, :float
    field :cortexiq_net_savings, :float

    field :simulation_time, :utc_datetime_usec
    field :simulation_speed, :integer

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(system_stats, attrs) do
    system_stats
    |> cast(attrs, [
      :total_homes,
      :total_providers,
      :total_production_kwh,
      :total_consumption_kwh,
      :total_energy_bought_kwh,
      :total_energy_sold_kwh,
      :total_cost_paid,
      :total_revenue_received,
      :contract_switches_count,
      :avg_battery_percent,
      :cortexiq_total_commission,
      :cortexiq_total_savings,
      :cortexiq_net_savings,
      :simulation_time,
      :simulation_speed
    ])
  end
end
