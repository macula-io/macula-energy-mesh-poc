defmodule CortexIqCore.ContractOffer do
  @moduledoc """
  Represents a contract offer published by a provider.

  Providers continuously publish their current contract offers.
  Homes subscribe to these offers and evaluate switching opportunities.
  """

  @type t :: %__MODULE__{
          offer_id: String.t(),
          provider_id: String.t(),
          duration_months: integer(),
          day_buy_price: float(),
          night_buy_price: float(),
          day_sell_price: float(),
          night_sell_price: float(),
          switching_discount: float(),
          minimum_monthly_kwh: float(),
          valid_from: DateTime.t()
        }

  @enforce_keys [
    :offer_id,
    :provider_id,
    :day_buy_price,
    :night_buy_price,
    :day_sell_price,
    :night_sell_price,
    :valid_from
  ]

  defstruct [
    :offer_id,
    :provider_id,
    :valid_from,
    :day_buy_price,
    :night_buy_price,
    :day_sell_price,
    :night_sell_price,
    duration_months: 12,
    switching_discount: 0.0,
    minimum_monthly_kwh: 0.0
  ]

  @doc """
  Create a new contract offer.
  """
  @spec new(String.t(), map(), DateTime.t()) :: t()
  def new(provider_id, pricing, valid_from) do
    %__MODULE__{
      offer_id: generate_offer_id(provider_id, valid_from),
      provider_id: provider_id,
      day_buy_price: pricing.day_buy_price,
      night_buy_price: pricing.night_buy_price,
      day_sell_price: pricing.day_sell_price,
      night_sell_price: pricing.night_sell_price,
      switching_discount: Map.get(pricing, :switching_discount, 0.0),
      minimum_monthly_kwh: Map.get(pricing, :minimum_monthly_kwh, 0.0),
      duration_months: Map.get(pricing, :duration_months, 12),
      valid_from: valid_from
    }
  end

  @doc """
  Convert offer to a map suitable for WAMP publishing.
  """
  @spec to_event(t(), DateTime.t()) :: map()
  def to_event(%__MODULE__{} = offer, simulation_time) do
    %{
      offer_id: offer.offer_id,
      provider_id: offer.provider_id,
      duration_months: offer.duration_months,
      day_buy_price: offer.day_buy_price,
      night_buy_price: offer.night_buy_price,
      day_sell_price: offer.day_sell_price,
      night_sell_price: offer.night_sell_price,
      switching_discount: offer.switching_discount,
      minimum_monthly_kwh: offer.minimum_monthly_kwh,
      valid_from: DateTime.to_iso8601(offer.valid_from),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }
  end

  @doc """
  Create offer from event data received via WAMP.
  """
  @spec from_event(map()) :: t()
  def from_event(event) do
    {:ok, valid_from, _} = DateTime.from_iso8601(event["valid_from"])

    %__MODULE__{
      offer_id: event["offer_id"],
      provider_id: event["provider_id"],
      duration_months: event["duration_months"],
      day_buy_price: event["day_buy_price"],
      night_buy_price: event["night_buy_price"],
      day_sell_price: event["day_sell_price"],
      night_sell_price: event["night_sell_price"],
      switching_discount: event["switching_discount"],
      minimum_monthly_kwh: event["minimum_monthly_kwh"],
      valid_from: valid_from
    }
  end

  @doc """
  Calculate average buy price (weighted by typical day/night usage).
  Assumes 60% day usage, 40% night usage.
  """
  @spec avg_buy_price(t()) :: float()
  def avg_buy_price(%__MODULE__{} = offer) do
    offer.day_buy_price * 0.6 + offer.night_buy_price * 0.4
  end

  @doc """
  Calculate average sell price (weighted by typical day/night production).
  Assumes 80% day production, 20% night production (solar-heavy).
  """
  @spec avg_sell_price(t()) :: float()
  def avg_sell_price(%__MODULE__{} = offer) do
    offer.day_sell_price * 0.8 + offer.night_sell_price * 0.2
  end

  # Private helpers

  defp generate_offer_id(provider_id, valid_from) do
    timestamp = DateTime.to_unix(valid_from)
    hash = :erlang.phash2({provider_id, timestamp})
    "offer_#{provider_id}_#{hash}"
  end
end
