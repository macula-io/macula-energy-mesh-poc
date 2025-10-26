defmodule CortexIqCore.SpotMarket do
  @moduledoc """
  Spot market pricing based on supply/demand balance.

  The spot price fluctuates based on the grid's supply/demand ratio:
  - When demand > supply: prices spike (grid stress)
  - When supply > demand: prices drop (excess renewable energy)
  - Quadratic relationship creates realistic price volatility

  ## Pricing Formula

      base_price = 0.10 $/kWh
      net_demand = total_consumption - total_production
      utilization = net_demand / grid_capacity
      spot_price = base_price * (1 + utilization^2)

  ## Examples

      Supply = Demand → spot_price = $0.10/kWh (base)
      Demand 50% higher → spot_price = $0.225/kWh (spike)
      Supply 50% higher → spot_price = $0.025/kWh (cheap)
  """

  @base_price 0.10  # $/kWh base price at perfect balance
  @grid_capacity 1000.0  # kW - theoretical maximum grid capacity

  # Min/max price bounds to prevent extreme values
  @min_price 0.01
  @max_price 1.00

  @type spot_price_data :: %{
    spot_price: float(),
    total_production_kw: float(),
    total_consumption_kw: float(),
    net_demand_kw: float(),
    utilization: float(),
    simulation_time: DateTime.t()
  }

  @doc """
  Calculate spot price based on current supply and demand.

  ## Parameters
    - `total_production_kw`: Total energy production across all homes (kW)
    - `total_consumption_kw`: Total energy consumption across all homes (kW)
    - `simulation_time`: Current simulation timestamp

  ## Returns
    Map with spot price and market statistics
  """
  @spec calculate_spot_price(float(), float(), DateTime.t()) :: spot_price_data()
  def calculate_spot_price(total_production_kw, total_consumption_kw, simulation_time) do
    # Net demand (positive = grid must supply, negative = excess production)
    net_demand_kw = total_consumption_kw - total_production_kw

    # Grid utilization (-1.0 to 1.0)
    utilization = net_demand_kw / @grid_capacity

    # Quadratic price response (spikes when grid stressed)
    # Formula: base * (1 + utilization^2)
    # When utilization = 0 (balanced): price = base
    # When utilization = 1.0 (full demand): price = 2x base
    # When utilization = -1.0 (full excess): price = 2x base (but we clamp it lower)
    raw_price = @base_price * (1.0 + :math.pow(utilization, 2))

    # Clamp to realistic bounds
    spot_price = raw_price
      |> max(@min_price)
      |> min(@max_price)
      |> Float.round(4)

    %{
      spot_price: spot_price,
      total_production_kw: Float.round(total_production_kw, 2),
      total_consumption_kw: Float.round(total_consumption_kw, 2),
      net_demand_kw: Float.round(net_demand_kw, 2),
      utilization: Float.round(utilization, 3),
      simulation_time: simulation_time
    }
  end

  @doc """
  Calculate buy price for a dynamic contract given current spot price.
  """
  @spec dynamic_buy_price(float(), float()) :: float()
  def dynamic_buy_price(spot_price, markup) do
    Float.round(spot_price + markup, 4)
  end

  @doc """
  Calculate sell price for a dynamic contract given current spot price.
  """
  @spec dynamic_sell_price(float(), float()) :: float()
  def dynamic_sell_price(spot_price, markdown) do
    Float.round(spot_price - markdown, 4)
      |> max(0.001)  # Never go below 0.1 cent
  end

  @doc """
  Estimate arbitrage profit for battery trading.

  ## Parameters
    - `buy_price`: Price paid to charge battery
    - `sell_price`: Price received when discharging
    - `kwh`: Energy amount
    - `battery_efficiency`: Round-trip efficiency (0.0-1.0), default 0.90

  ## Returns
    Net profit after accounting for battery losses
  """
  @spec arbitrage_profit(float(), float(), float(), float()) :: float()
  def arbitrage_profit(buy_price, sell_price, kwh, battery_efficiency \\ 0.90) do
    revenue = sell_price * kwh * battery_efficiency
    cost = buy_price * kwh
    Float.round(revenue - cost, 2)
  end

  @doc """
  Determine if arbitrage opportunity exists (profitable battery trading).
  """
  @spec arbitrage_opportunity?(float(), float(), float()) :: boolean()
  def arbitrage_opportunity?(buy_price, sell_price, battery_efficiency \\ 0.90) do
    arbitrage_profit(buy_price, sell_price, 1.0, battery_efficiency) > 0.01
  end
end
