defmodule CortexIqCore.SpotPrice do
  @moduledoc """
  Represents spot market pricing for homes without active contracts.

  Spot prices are:
  - More volatile than contract prices
  - Generally less favorable (to encourage contract adoption)
  - Updated more frequently
  """

  @type t :: %__MODULE__{
          provider_id: String.t(),
          buy_price: float(),
          sell_price: float(),
          valid_from: DateTime.t()
        }

  @enforce_keys [:provider_id, :buy_price, :sell_price, :valid_from]

  defstruct [:provider_id, :buy_price, :sell_price, :valid_from]

  @doc """
  Create a new spot price.
  """
  @spec new(String.t(), float(), float(), DateTime.t()) :: t()
  def new(provider_id, buy_price, sell_price, valid_from) do
    %__MODULE__{
      provider_id: provider_id,
      buy_price: buy_price,
      sell_price: sell_price,
      valid_from: valid_from
    }
  end

  @doc """
  Convert spot price to event map for WAMP publishing.
  """
  @spec to_event(t(), DateTime.t()) :: map()
  def to_event(%__MODULE__{} = spot_price, simulation_time) do
    %{
      provider_id: spot_price.provider_id,
      buy_price: spot_price.buy_price,
      sell_price: spot_price.sell_price,
      valid_from: DateTime.to_iso8601(spot_price.valid_from),
      simulation_time: DateTime.to_iso8601(simulation_time)
    }
  end

  @doc """
  Create spot price from event data received via WAMP.
  """
  @spec from_event(map()) :: t()
  def from_event(event) do
    {:ok, valid_from, _} = DateTime.from_iso8601(event["valid_from"])

    %__MODULE__{
      provider_id: event["provider_id"],
      buy_price: event["buy_price"],
      sell_price: event["sell_price"],
      valid_from: valid_from
    }
  end
end
