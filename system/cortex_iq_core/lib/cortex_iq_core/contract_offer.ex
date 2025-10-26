defmodule CortexIqCore.ContractOffer do
  @moduledoc """
  Represents a contract offer published by a provider.

  Providers continuously publish their current contract offers.
  Homes subscribe to these offers and evaluate switching opportunities.

  ## Contract Types

  **Static Contract**: Fixed prices for the contract duration.
  - `day_buy_price`, `night_buy_price`: Fixed $/kWh when buying
  - `day_sell_price`, `night_sell_price`: Fixed $/kWh when selling
  - Predictable costs, safe for risk-averse customers

  **Dynamic Contract**: Prices track spot market with markup/markdown.
  - `buy_markup`: Added to spot price when buying (e.g., spot + $0.02)
  - `sell_markdown`: Subtracted from spot price when selling (e.g., spot - $0.01)
  - Actual prices fluctuate with market, potentially cheaper but riskier
  """

  @type contract_type :: :static | :dynamic

  @type t :: %__MODULE__{
          offer_id: String.t(),
          provider_id: String.t(),
          contract_type: contract_type(),
          duration_months: integer(),
          # Static contract fields (nil for dynamic)
          day_buy_price: float() | nil,
          night_buy_price: float() | nil,
          day_sell_price: float() | nil,
          night_sell_price: float() | nil,
          # Dynamic contract fields (nil for static)
          buy_markup: float() | nil,
          sell_markdown: float() | nil,
          switching_discount: float(),
          minimum_monthly_kwh: float(),
          valid_from: DateTime.t()
        }

  @enforce_keys [
    :offer_id,
    :provider_id,
    :contract_type,
    :valid_from
  ]

  defstruct [
    :offer_id,
    :provider_id,
    :contract_type,
    :valid_from,
    :day_buy_price,
    :night_buy_price,
    :day_sell_price,
    :night_sell_price,
    :buy_markup,
    :sell_markdown,
    duration_months: 12,
    switching_discount: 0.0,
    minimum_monthly_kwh: 0.0
  ]

  @doc """
  Create a new static contract offer with fixed prices.
  """
  @spec new_static(String.t(), map(), DateTime.t()) :: t()
  def new_static(provider_id, pricing, valid_from) do
    %__MODULE__{
      offer_id: generate_offer_id(provider_id, valid_from),
      provider_id: provider_id,
      contract_type: :static,
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
  Create a new dynamic contract offer with spot-based pricing.
  """
  @spec new_dynamic(String.t(), map(), DateTime.t()) :: t()
  def new_dynamic(provider_id, pricing, valid_from) do
    %__MODULE__{
      offer_id: generate_offer_id(provider_id, valid_from),
      provider_id: provider_id,
      contract_type: :dynamic,
      buy_markup: pricing.buy_markup,
      sell_markdown: pricing.sell_markdown,
      switching_discount: Map.get(pricing, :switching_discount, 0.0),
      minimum_monthly_kwh: Map.get(pricing, :minimum_monthly_kwh, 0.0),
      duration_months: Map.get(pricing, :duration_months, 12),
      valid_from: valid_from
    }
  end

  @doc """
  Create a new contract offer (backward compatibility).
  Defaults to static contract.
  """
  @spec new(String.t(), map(), DateTime.t()) :: t()
  def new(provider_id, pricing, valid_from) do
    contract_type = Map.get(pricing, :contract_type, :static)

    case contract_type do
      :dynamic -> new_dynamic(provider_id, pricing, valid_from)
      :static -> new_static(provider_id, pricing, valid_from)
    end
  end

  @doc """
  Convert offer to a map suitable for WAMP publishing.
  """
  @spec to_event(t(), DateTime.t()) :: map()
  def to_event(%__MODULE__{contract_type: :static} = offer, simulation_time) do
    %{
      offer_id: offer.offer_id,
      provider_id: offer.provider_id,
      contract_type: "static",
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

  def to_event(%__MODULE__{contract_type: :dynamic} = offer, simulation_time) do
    %{
      offer_id: offer.offer_id,
      provider_id: offer.provider_id,
      contract_type: "dynamic",
      duration_months: offer.duration_months,
      buy_markup: offer.buy_markup,
      sell_markdown: offer.sell_markdown,
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
    contract_type = String.to_existing_atom(event["contract_type"] || "static")

    case contract_type do
      :static ->
        %__MODULE__{
          offer_id: event["offer_id"],
          provider_id: event["provider_id"],
          contract_type: :static,
          duration_months: event["duration_months"],
          day_buy_price: event["day_buy_price"],
          night_buy_price: event["night_buy_price"],
          day_sell_price: event["day_sell_price"],
          night_sell_price: event["night_sell_price"],
          switching_discount: event["switching_discount"],
          minimum_monthly_kwh: event["minimum_monthly_kwh"],
          valid_from: valid_from
        }

      :dynamic ->
        %__MODULE__{
          offer_id: event["offer_id"],
          provider_id: event["provider_id"],
          contract_type: :dynamic,
          duration_months: event["duration_months"],
          buy_markup: event["buy_markup"],
          sell_markdown: event["sell_markdown"],
          switching_discount: event["switching_discount"],
          minimum_monthly_kwh: event["minimum_monthly_kwh"],
          valid_from: valid_from
        }
    end
  end

  @doc """
  Calculate buy price for a given spot price and time of day.

  For static contracts: returns fixed price.
  For dynamic contracts: returns spot + markup.
  """
  @spec buy_price(t(), float() | nil, boolean()) :: float()
  def buy_price(%__MODULE__{contract_type: :static, day_buy_price: day, night_buy_price: night}, _spot_price, is_day) do
    if is_day, do: day, else: night
  end

  def buy_price(%__MODULE__{contract_type: :dynamic, buy_markup: markup}, spot_price, _is_day) when not is_nil(spot_price) do
    CortexIqCore.SpotMarket.dynamic_buy_price(spot_price, markup)
  end

  @doc """
  Calculate sell price for a given spot price and time of day.

  For static contracts: returns fixed price.
  For dynamic contracts: returns spot - markdown.
  """
  @spec sell_price(t(), float() | nil, boolean()) :: float()
  def sell_price(%__MODULE__{contract_type: :static, day_sell_price: day, night_sell_price: night}, _spot_price, is_day) do
    if is_day, do: day, else: night
  end

  def sell_price(%__MODULE__{contract_type: :dynamic, sell_markdown: markdown}, spot_price, _is_day) when not is_nil(spot_price) do
    CortexIqCore.SpotMarket.dynamic_sell_price(spot_price, markdown)
  end

  @doc """
  Calculate average buy price (weighted by typical day/night usage).
  Assumes 60% day usage, 40% night usage.

  For dynamic contracts, requires spot_price parameter.
  """
  @spec avg_buy_price(t(), float() | nil) :: float()
  def avg_buy_price(%__MODULE__{contract_type: :static} = offer, _spot_price \\ nil) do
    offer.day_buy_price * 0.6 + offer.night_buy_price * 0.4
  end

  def avg_buy_price(%__MODULE__{contract_type: :dynamic, buy_markup: markup}, spot_price) when not is_nil(spot_price) do
    CortexIqCore.SpotMarket.dynamic_buy_price(spot_price, markup)
  end

  @doc """
  Calculate average sell price (weighted by typical day/night production).
  Assumes 80% day production, 20% night production (solar-heavy).

  For dynamic contracts, requires spot_price parameter.
  """
  @spec avg_sell_price(t(), float() | nil) :: float()
  def avg_sell_price(%__MODULE__{contract_type: :static} = offer, _spot_price \\ nil) do
    offer.day_sell_price * 0.8 + offer.night_sell_price * 0.2
  end

  def avg_sell_price(%__MODULE__{contract_type: :dynamic, sell_markdown: markdown}, spot_price) when not is_nil(spot_price) do
    CortexIqCore.SpotMarket.dynamic_sell_price(spot_price, markdown)
  end

  # Private helpers

  defp generate_offer_id(provider_id, valid_from) do
    timestamp = DateTime.to_unix(valid_from)
    hash = :erlang.phash2({provider_id, timestamp})
    "offer_#{provider_id}_#{hash}"
  end
end
