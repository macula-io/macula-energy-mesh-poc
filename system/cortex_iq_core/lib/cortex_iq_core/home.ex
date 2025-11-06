defmodule CortexIqCore.Home do
  @moduledoc """
  Represents a home in the energy mesh.

  Each home has:
  - Solar/wind production capabilities
  - Energy consumption patterns
  - Battery storage
  - A location in Belgium
  - An active contract or spot market access
  """

  alias CortexIqCore.Geography

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t() | nil,
          iot_provider: String.t() | nil,
          meter_ean: String.t() | nil,
          # Multi-meter EANs (18-digit European Article Numbers)
          electricity_day_meter_ean: String.t() | nil,
          electricity_night_meter_ean: String.t() | nil,
          gas_meter_ean: String.t() | nil,
          water_meter_ean: String.t() | nil,
          location: Geography.location(),
          solar_capacity_kw: float(),
          battery_capacity_kwh: float(),
          current_contract_id: String.t() | nil
        }

  @enforce_keys [:id, :location]

  defstruct [
    :id,
    :name,
    :iot_provider,
    :meter_ean,  # Legacy field - kept for backward compatibility
    # Multi-meter EANs (18-digit European Article Numbers)
    :electricity_day_meter_ean,
    :electricity_night_meter_ean,
    :gas_meter_ean,
    :water_meter_ean,
    :location,
    :current_contract_id,
    solar_capacity_kw: 5.0,
    battery_capacity_kwh: 10.0
  ]

  @doc """
  Create a new home with random location and default capacities.
  """
  @spec new(String.t()) :: t()
  def new(home_id) do
    %__MODULE__{
      id: home_id,
      location: Geography.location_for_home(home_id),
      solar_capacity_kw: random_solar_capacity(),
      battery_capacity_kwh: random_battery_capacity(),
      current_contract_id: nil
    }
  end

  @doc """
  Create a new home with specific parameters.
  """
  @spec new(String.t(), map()) :: t()
  def new(home_id, opts) do
    %__MODULE__{
      id: home_id,
      name: Map.get(opts, :name),
      iot_provider: Map.get(opts, :iot_provider),
      meter_ean: Map.get(opts, :meter_ean),
      # Multi-meter EANs
      electricity_day_meter_ean: Map.get(opts, :electricity_day_meter_ean),
      electricity_night_meter_ean: Map.get(opts, :electricity_night_meter_ean),
      gas_meter_ean: Map.get(opts, :gas_meter_ean),
      water_meter_ean: Map.get(opts, :water_meter_ean),
      location: Map.get(opts, :location, Geography.location_for_home(home_id)),
      solar_capacity_kw: Map.get(opts, :solar_capacity_kw, random_solar_capacity()),
      battery_capacity_kwh: Map.get(opts, :battery_capacity_kwh, random_battery_capacity()),
      current_contract_id: Map.get(opts, :current_contract_id)
    }
  end

  @doc """
  Update home's current contract.
  """
  @spec set_contract(t(), String.t()) :: t()
  def set_contract(%__MODULE__{} = home, contract_id) do
    %{home | current_contract_id: contract_id}
  end

  @doc """
  Clear home's current contract (move to spot market).
  """
  @spec clear_contract(t()) :: t()
  def clear_contract(%__MODULE__{} = home) do
    %{home | current_contract_id: nil}
  end

  @doc """
  Check if home has an active contract.
  """
  @spec has_contract?(t()) :: boolean()
  def has_contract?(%__MODULE__{current_contract_id: nil}), do: false
  def has_contract?(%__MODULE__{}), do: true

  # Private helpers

  defp random_solar_capacity do
    # 3-7 kW typical residential solar
    3.0 + :rand.uniform() * 4.0
  end

  defp random_battery_capacity do
    # 5-15 kWh typical home battery
    5.0 + :rand.uniform() * 10.0
  end
end
