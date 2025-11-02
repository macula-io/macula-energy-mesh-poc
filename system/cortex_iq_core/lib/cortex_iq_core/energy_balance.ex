defmodule CortexIqCore.EnergyBalance do
  @moduledoc """
  Tracks energy bought and sold by a home over a contract period.

  The goal for homes is to minimize: energy_bought - energy_sold

  This involves:
  - Buying energy at cheap times (low rates or when solar/wind unavailable)
  - Selling energy at expensive times (high rates or using battery)
  - Optimizing battery charge/discharge to shift energy across time periods
  """

  alias CortexIqCore.DateTimeHelpers

  @type t :: %__MODULE__{
          home_id: String.t(),
          contract_id: String.t() | nil,
          period_start: DateTime.t(),
          period_end: DateTime.t(),
          energy_bought_kwh: float(),
          energy_sold_kwh: float(),
          cost_paid: float(),
          revenue_received: float()
        }

  defstruct [
    :home_id,
    :contract_id,
    :period_start,
    :period_end,
    energy_bought_kwh: 0.0,
    energy_sold_kwh: 0.0,
    cost_paid: 0.0,
    revenue_received: 0.0
  ]

  @doc """
  Create a new energy balance tracker.
  """
  @spec new(String.t(), String.t() | nil, DateTime.t()) :: t()
  def new(home_id, contract_id, period_start) do
    %__MODULE__{
      home_id: home_id,
      contract_id: contract_id,
      period_start: period_start,
      period_end: period_start
    }
  end

  @doc """
  Record an energy purchase (home buys from provider).
  """
  @spec record_buy(t(), float(), float(), DateTime.t()) :: t()
  def record_buy(%__MODULE__{} = balance, kwh, price_per_kwh, timestamp) do
    cost = kwh * price_per_kwh

    %{
      balance
      | energy_bought_kwh: balance.energy_bought_kwh + kwh,
        cost_paid: balance.cost_paid + cost,
        period_end: timestamp
    }
  end

  @doc """
  Record an energy sale (home sells to provider).
  """
  @spec record_sell(t(), float(), float(), DateTime.t()) :: t()
  def record_sell(%__MODULE__{} = balance, kwh, price_per_kwh, timestamp) do
    revenue = kwh * price_per_kwh

    %{
      balance
      | energy_sold_kwh: balance.energy_sold_kwh + kwh,
        revenue_received: balance.revenue_received + revenue,
        period_end: timestamp
    }
  end

  @doc """
  Calculate net energy balance (bought - sold).
  Positive means net consumer, negative means net producer.
  """
  @spec net_balance_kwh(t()) :: float()
  def net_balance_kwh(%__MODULE__{} = balance) do
    balance.energy_bought_kwh - balance.energy_sold_kwh
  end

  @doc """
  Calculate net cost (paid - received).
  """
  @spec net_cost(t()) :: float()
  def net_cost(%__MODULE__{} = balance) do
    balance.cost_paid - balance.revenue_received
  end

  @doc """
  Calculate average buy price per kWh.
  """
  @spec avg_buy_price(t()) :: float()
  def avg_buy_price(%__MODULE__{} = balance) when balance.energy_bought_kwh == 0, do: 0.0

  def avg_buy_price(%__MODULE__{} = balance) do
    balance.cost_paid / balance.energy_bought_kwh
  end

  @doc """
  Calculate average sell price per kWh.
  """
  @spec avg_sell_price(t()) :: float()
  def avg_sell_price(%__MODULE__{} = balance) when balance.energy_sold_kwh == 0, do: 0.0

  def avg_sell_price(%__MODULE__{} = balance) do
    balance.revenue_received / balance.energy_sold_kwh
  end

  @doc """
  Convert balance to event map for WAMP publishing.
  """
  @spec to_event(t(), DateTime.t()) :: map()
  def to_event(%__MODULE__{} = balance, simulation_time) do
    %{
      home_id: balance.home_id,
      contract_id: balance.contract_id,
      period_start: DateTimeHelpers.to_iso8601(balance.period_start),
      period_end: DateTimeHelpers.to_iso8601(balance.period_end),
      energy_bought_kwh: Float.round(balance.energy_bought_kwh, 2),
      energy_sold_kwh: Float.round(balance.energy_sold_kwh, 2),
      net_balance_kwh: Float.round(net_balance_kwh(balance), 2),
      cost_paid: Float.round(balance.cost_paid, 2),
      revenue_received: Float.round(balance.revenue_received, 2),
      net_cost: Float.round(net_cost(balance), 2),
      simulation_time: DateTimeHelpers.to_iso8601(simulation_time)
    }
  end

  @doc """
  Estimate future balance projection over N days with given contract.
  Uses current daily averages to project forward.
  """
  @spec project_balance(t(), CortexIqCore.Contract.t(), integer()) :: float()
  def project_balance(%__MODULE__{} = balance, _contract, days) do
    # Calculate current daily average
    period_days = max(1, CortexIqCore.SimulationTime.days_between(balance.period_start, balance.period_end))
    daily_net_kwh = net_balance_kwh(balance) / period_days

    # Project forward
    daily_net_kwh * days
  end

  @doc """
  Estimate future cost projection over N days with given contract.
  """
  @spec project_cost(t(), CortexIqCore.Contract.t(), integer()) :: float()
  def project_cost(%__MODULE__{} = balance, _contract, days) do
    # Calculate current daily average
    period_days = max(1, CortexIqCore.SimulationTime.days_between(balance.period_start, balance.period_end))
    daily_net_cost = net_cost(balance) / period_days

    # Project forward
    daily_net_cost * days
  end
end
