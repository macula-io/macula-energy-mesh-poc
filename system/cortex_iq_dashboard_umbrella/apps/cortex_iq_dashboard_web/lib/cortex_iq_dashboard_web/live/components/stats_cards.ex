defmodule CortexIqDashboardWeb.Components.StatsCards do
  @moduledoc """
  LiveComponent for system-wide statistics cards.

  Displays 6 key metrics:
  - Connected Homes
  - Energy Bought (with cost)
  - Energy Sold (with revenue)
  - Net Balance (with net cost)
  - Average Battery %
  - Contract Switches
  """
  use CortexIqDashboardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-6 gap-4 mb-6">
      <!-- Connected Homes -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Connected Homes</div>
        <div class="text-2xl font-bold text-green-400">{@stats.homes}</div>
      </div>

      <!-- Energy Bought -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Energy Bought</div>
        <div class="text-lg font-bold text-red-400">
          {format_energy(@stats.total_energy_bought_kwh)}
        </div>
        <div class="text-xs text-gray-500 mt-1">
          €{Float.round(@stats.total_cost_paid, 2)}
        </div>
      </div>

      <!-- Energy Sold -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Energy Sold</div>
        <div class="text-lg font-bold text-green-400">
          {format_energy(@stats.total_energy_sold_kwh)}
        </div>
        <div class="text-xs text-gray-500 mt-1">
          €{Float.round(@stats.total_revenue_received, 2)}
        </div>
      </div>

      <!-- Net Balance -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Net Balance</div>
        <div class={"text-lg font-bold #{if @stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh > 0, do: "text-red-400", else: "text-green-400"}"}>
          {format_energy(abs(@stats.total_energy_bought_kwh - @stats.total_energy_sold_kwh))}
        </div>
        <div class="text-xs text-gray-500 mt-1">
          Net: €{Float.round(@stats.total_cost_paid - @stats.total_revenue_received, 2)}
        </div>
      </div>

      <!-- Average Battery -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Avg Battery</div>
        <div class="text-2xl font-bold text-blue-400">
          {Float.round(@stats.avg_battery_percent, 1)}%
        </div>
      </div>

      <!-- Contract Switches -->
      <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
        <div class="text-gray-400 text-xs">Contract Switches</div>
        <div class="text-2xl font-bold text-purple-400">{@stats.contract_switches}</div>
      </div>
    </div>
    """
  end

  # Helper functions

  defp format_energy(kwh) when kwh >= 1000.0 do
    "#{Float.round(kwh / 1000.0, 2)} MWh"
  end
  defp format_energy(kwh) do
    "#{Float.round(kwh, 2)} kWh"
  end
end
