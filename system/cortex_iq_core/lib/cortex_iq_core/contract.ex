defmodule CortexIqCore.Contract do
  @moduledoc """
  Represents an energy supply contract between a home and a provider.

  A contract defines:
  - Duration (typically 12 months)
  - Pricing: separate buy/sell rates for day/night periods
  - Switching discount (applied day before expiry if not switched early)
  - Minimum energy purchase requirements
  """

  @type t :: %__MODULE__{
          id: String.t(),
          home_id: String.t(),
          provider_id: String.t(),
          offer_id: String.t(),
          start_date: DateTime.t(),
          end_date: DateTime.t(),
          day_buy_price: float(),
          night_buy_price: float(),
          day_sell_price: float(),
          night_sell_price: float(),
          switching_discount: float(),
          minimum_monthly_kwh: float(),
          status: :active | :expired | :cancelled,
          reason: :new | :renewal | :switch,
          discount_applied: boolean()
        }

  @enforce_keys [
    :id,
    :home_id,
    :provider_id,
    :offer_id,
    :start_date,
    :end_date,
    :day_buy_price,
    :night_buy_price,
    :day_sell_price,
    :night_sell_price
  ]

  defstruct [
    :id,
    :home_id,
    :provider_id,
    :offer_id,
    :start_date,
    :end_date,
    :day_buy_price,
    :night_buy_price,
    :day_sell_price,
    :night_sell_price,
    switching_discount: 0.0,
    minimum_monthly_kwh: 0.0,
    status: :active,
    reason: :new,
    discount_applied: false
  ]

  @doc """
  Create a new contract from a contract offer.
  """
  @spec from_offer(map(), String.t(), DateTime.t(), atom()) :: t()
  def from_offer(offer, home_id, start_date, reason \\ :new) do
    duration_months = Map.get(offer, :duration_months, 12)
    end_date = CortexIqCore.SimulationTime.add_months(start_date, duration_months)

    %__MODULE__{
      id: generate_id(home_id, offer.provider_id, start_date),
      home_id: home_id,
      provider_id: offer.provider_id,
      offer_id: offer.offer_id,
      start_date: start_date,
      end_date: end_date,
      day_buy_price: offer.day_buy_price,
      night_buy_price: offer.night_buy_price,
      day_sell_price: offer.day_sell_price,
      night_sell_price: offer.night_sell_price,
      switching_discount: Map.get(offer, :switching_discount, 0.0),
      minimum_monthly_kwh: Map.get(offer, :minimum_monthly_kwh, 0.0),
      status: :active,
      reason: reason,
      discount_applied: false
    }
  end

  @doc """
  Check if contract is expired at given simulation time.
  """
  @spec expired?(t(), DateTime.t()) :: boolean()
  def expired?(%__MODULE__{} = contract, current_time) do
    DateTime.compare(current_time, contract.end_date) != :lt
  end

  @doc """
  Check if contract is in discount window (1 day before expiry).
  """
  @spec in_discount_window?(t(), DateTime.t()) :: boolean()
  def in_discount_window?(%__MODULE__{} = contract, current_time) do
    CortexIqCore.SimulationTime.within_discount_window?(current_time, contract.end_date)
  end

  @doc """
  Get the appropriate buy price based on time of day.
  """
  @spec buy_price(t(), DateTime.t()) :: float()
  def buy_price(%__MODULE__{} = contract, simulation_time) do
    if CortexIqCore.SimulationTime.is_day?(simulation_time) do
      contract.day_buy_price
    else
      contract.night_buy_price
    end
  end

  @doc """
  Get the appropriate sell price based on time of day.
  """
  @spec sell_price(t(), DateTime.t()) :: float()
  def sell_price(%__MODULE__{} = contract, simulation_time) do
    if CortexIqCore.SimulationTime.is_day?(simulation_time) do
      contract.day_sell_price
    else
      contract.night_sell_price
    end
  end

  @doc """
  Calculate days remaining in contract.
  """
  @spec days_remaining(t(), DateTime.t()) :: integer()
  def days_remaining(%__MODULE__{} = contract, current_time) do
    max(0, CortexIqCore.SimulationTime.days_between(current_time, contract.end_date))
  end

  @doc """
  Mark contract as expired.
  """
  @spec expire(t()) :: t()
  def expire(%__MODULE__{} = contract) do
    %{contract | status: :expired}
  end

  @doc """
  Mark contract as cancelled (switched early).
  """
  @spec cancel(t()) :: t()
  def cancel(%__MODULE__{} = contract) do
    %{contract | status: :cancelled}
  end

  @doc """
  Apply switching discount to contract.
  """
  @spec apply_discount(t()) :: t()
  def apply_discount(%__MODULE__{} = contract) do
    %{contract | discount_applied: true}
  end

  # Private helpers

  defp generate_id(home_id, provider_id, start_date) do
    timestamp = DateTime.to_unix(start_date)
    "contract_#{home_id}_#{provider_id}_#{timestamp}"
  end
end
