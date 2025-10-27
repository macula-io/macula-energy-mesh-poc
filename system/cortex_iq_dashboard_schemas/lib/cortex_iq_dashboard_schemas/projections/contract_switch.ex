defmodule CortexIqDashboardSchemas.Projections.ContractSwitch do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "contract_switches" do
    field :home_id, :string
    field :home_name, :string

    # Contract switch details
    field :from_provider_id, :string
    field :to_provider_id, :string
    field :from_contract_id, :string
    field :to_contract_id, :string

    # Financial details
    field :gross_savings, :float
    field :cortexiq_commission, :float
    field :net_savings_to_customer, :float
    field :commission_rate, :float

    # Cumulative totals at time of switch
    field :cumulative_commission, :float
    field :cumulative_gross_savings, :float
    field :cumulative_net_savings, :float
    field :total_switches, :integer

    # Timing
    field :simulation_time, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(contract_switch, attrs) do
    contract_switch
    |> cast(attrs, [
      :home_id,
      :home_name,
      :from_provider_id,
      :to_provider_id,
      :from_contract_id,
      :to_contract_id,
      :gross_savings,
      :cortexiq_commission,
      :net_savings_to_customer,
      :commission_rate,
      :cumulative_commission,
      :cumulative_gross_savings,
      :cumulative_net_savings,
      :total_switches,
      :simulation_time
    ])
    |> validate_required([:home_id, :from_provider_id, :to_provider_id, :gross_savings, :cortexiq_commission, :net_savings_to_customer, :simulation_time])
  end
end
