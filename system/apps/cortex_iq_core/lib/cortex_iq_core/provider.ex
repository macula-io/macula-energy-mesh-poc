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

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          strategy: strategy(),
          base_day_buy_price: float(),
          base_night_buy_price: float(),
          base_day_sell_price: float(),
          base_night_sell_price: float(),
          switching_discount: float(),
          minimum_monthly_kwh: float()
        }

  @enforce_keys [:id, :name, :strategy]

  defstruct [
    :id,
    :name,
    :strategy,
    base_day_buy_price: 0.15,
    base_night_buy_price: 0.08,
    base_day_sell_price: 0.10,
    base_night_sell_price: 0.05,
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
      base_day_buy_price: base_pricing.day_buy,
      base_night_buy_price: base_pricing.night_buy,
      base_day_sell_price: base_pricing.day_sell,
      base_night_sell_price: base_pricing.night_sell,
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
      day_buy: 0.15,
      night_buy: 0.12,
      day_sell: 0.10,
      night_sell: 0.08,
      discount: 15.0,
      minimum: 50.0
    }
  end

  defp strategy_pricing(:night_owl) do
    %{
      day_buy: 0.22,
      # Expensive during day
      night_buy: 0.06,
      # Very cheap at night (50% discount)
      day_sell: 0.12,
      night_sell: 0.04,
      discount: 50.0,
      # Big discount to attract customers
      minimum: 100.0
    }
  end

  defp strategy_pricing(:solar_surfer) do
    %{
      day_buy: 0.12,
      # Cheap during solar hours
      night_buy: 0.20,
      # Expensive at night
      day_sell: 0.11,
      # Good sell-back during day
      night_sell: 0.05,
      discount: 20.0,
      minimum: 75.0
    }
  end

  defp strategy_pricing(:peak_predator) do
    %{
      day_buy: 0.18,
      # High during consumption peaks
      night_buy: 0.10,
      day_sell: 0.09,
      night_sell: 0.06,
      discount: 25.0,
      minimum: 80.0
    }
  end

  defp strategy_pricing(:discount_king) do
    %{
      day_buy: 0.14,
      # Competitive rates
      night_buy: 0.09,
      day_sell: 0.10,
      night_sell: 0.07,
      discount: 75.0,
      # Huge discount!
      minimum: 150.0
      # But high minimum
    }
  end
end
