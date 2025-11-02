defmodule CortexIqCore.Provider do
  @moduledoc """
  Represents an energy provider in the mesh.

  Each provider has:
  - A unique pricing strategy
  - Contract offer terms
  - Spot market prices
  - Market share goals
  """

  @type strategy ::
          :steady_eddie
          | :night_owl
          | :solar_surfer
          | :peak_predator
          | :discount_king

  @type contract_type_mix :: :all_static | :all_dynamic | :mixed

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          country: String.t() | nil,
          regions: [String.t()] | nil,
          headquarters: String.t() | nil,
          description: String.t() | nil,
          market_share_target: float(),
          strategy: strategy(),
          contract_type_mix: contract_type_mix(),
          dynamic_percentage: float(),
          # Static contract pricing
          base_day_buy_price: float(),
          base_night_buy_price: float(),
          base_day_sell_price: float(),
          base_night_sell_price: float(),
          # Dynamic contract pricing
          buy_markup: float(),
          sell_markdown: float(),
          switching_discount: float(),
          minimum_monthly_kwh: float()
        }

  @enforce_keys [:id, :name, :strategy]

  defstruct [
    :id,
    :name,
    :country,
    :regions,
    :headquarters,
    :description,
    :strategy,
    market_share_target: 0.15,
    contract_type_mix: :all_static,
    dynamic_percentage: 0.0,
    base_day_buy_price: 0.15,
    base_night_buy_price: 0.08,
    base_day_sell_price: 0.10,
    base_night_sell_price: 0.05,
    buy_markup: 0.02,
    sell_markdown: 0.01,
    switching_discount: 25.0,
    minimum_monthly_kwh: 100.0
  ]

  @doc """
  Create a new provider with predefined strategy.
  """
  @spec new(String.t(), String.t(), strategy()) :: t()
  def new(provider_id, name, strategy) do
    base_pricing = strategy_pricing(strategy)

    %__MODULE__{
      id: provider_id,
      name: name,
      strategy: strategy,
      contract_type_mix: base_pricing.contract_type_mix,
      dynamic_percentage: base_pricing.dynamic_percentage,
      base_day_buy_price: base_pricing.day_buy,
      base_night_buy_price: base_pricing.night_buy,
      base_day_sell_price: base_pricing.day_sell,
      base_night_sell_price: base_pricing.night_sell,
      buy_markup: base_pricing.buy_markup,
      sell_markdown: base_pricing.sell_markdown,
      switching_discount: base_pricing.discount,
      minimum_monthly_kwh: base_pricing.minimum
    }
  end

  @doc """
  Get all predefined providers.
  """
  @spec all() :: [t()]
  def all do
    [
      new("provider_a", "Steady Eddie Energy", :steady_eddie),
      new("provider_b", "Night Owl Power", :night_owl),
      new("provider_c", "Solar Surfer Electric", :solar_surfer),
      new("provider_d", "Peak Predator Energy", :peak_predator),
      new("provider_e", "Discount King Power", :discount_king)
    ]
  end

  @doc """
  Get provider by ID.
  """
  @spec get(String.t()) :: t() | nil
  def get(provider_id) do
    Enum.find(all(), &(&1.id == provider_id))
  end

  # Strategy-specific base pricing
  # These are base values that can be modified by time-based calculations

  defp strategy_pricing(:steady_eddie) do
    %{
      contract_type_mix: :all_static,
      dynamic_percentage: 0.0,
      day_buy: 0.15,
      night_buy: 0.12,
      day_sell: 0.10,
      night_sell: 0.08,
      buy_markup: 0.02,  # Not used for all_static, but provided
      sell_markdown: 0.01,
      discount: 15.0,
      minimum: 50.0
    }
  end

  defp strategy_pricing(:night_owl) do
    %{
      contract_type_mix: :all_static,
      dynamic_percentage: 0.0,
      day_buy: 0.22,  # Expensive during day
      night_buy: 0.06,  # Very cheap at night (50% discount)
      day_sell: 0.12,
      night_sell: 0.04,
      buy_markup: 0.02,
      sell_markdown: 0.01,
      discount: 50.0,  # Big discount to attract customers
      minimum: 100.0
    }
  end

  defp strategy_pricing(:solar_surfer) do
    %{
      contract_type_mix: :mixed,
      dynamic_percentage: 0.70,  # 70% dynamic contracts
      day_buy: 0.12,  # Cheap during solar hours
      night_buy: 0.20,  # Expensive at night
      day_sell: 0.11,  # Good sell-back during day
      night_sell: 0.05,
      buy_markup: 0.015,  # Lower markup for competitive dynamic contracts
      sell_markdown: 0.01,
      discount: 20.0,
      minimum: 75.0
    }
  end

  defp strategy_pricing(:peak_predator) do
    %{
      contract_type_mix: :all_static,
      dynamic_percentage: 0.0,
      day_buy: 0.18,  # High during consumption peaks
      night_buy: 0.10,
      day_sell: 0.09,
      night_sell: 0.06,
      buy_markup: 0.02,
      sell_markdown: 0.01,
      discount: 25.0,
      minimum: 80.0
    }
  end

  defp strategy_pricing(:discount_king) do
    %{
      contract_type_mix: :all_dynamic,
      dynamic_percentage: 1.0,  # 100% dynamic contracts
      day_buy: 0.14,  # Competitive rates (not used for all_dynamic)
      night_buy: 0.09,
      day_sell: 0.10,
      night_sell: 0.07,
      buy_markup: 0.01,  # Very aggressive markup - lowest in market
      sell_markdown: 0.015,  # Higher markdown but still competitive
      discount: 75.0,  # Huge discount!
      minimum: 150.0  # But high minimum
    }
  end
end
