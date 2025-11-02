defmodule CortexIqDashboardWeb.Components.FinancialSummary do
  @moduledoc """
  LiveComponent for CortexIQ platform financial summary.

  Displays 4 financial cards:
  - Customer Savings (Gross)
  - CortexIQ Revenue (20% commission)
  - Customer Savings (Net after commission)
  - Customer ROI
  """
  use CortexIqDashboardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-sm font-semibold text-gray-400 mb-3">CortexIQ Platform Revenue - Savings Optimization Service</h3>
      <div class="grid grid-cols-4 gap-4">
        <!-- Total Customer Savings -->
        <div class="bg-gradient-to-br from-green-900 to-green-800 rounded-lg p-4 border-2 border-green-600">
          <div class="text-gray-300 text-xs">Customer Savings (Gross)</div>
          <div class="text-3xl font-bold text-green-300">
            €{Float.round(@stats.cortexiq_total_savings, 2)}
          </div>
          <div class="text-xs text-green-400 mt-1">
            From {@stats.contract_switches} switches
          </div>
        </div>

        <!-- CortexIQ Commission -->
        <div class="bg-gradient-to-br from-yellow-900 to-yellow-800 rounded-lg p-4 border-2 border-yellow-600">
          <div class="text-gray-300 text-xs">CortexIQ Revenue (20%)</div>
          <div class="text-3xl font-bold text-yellow-300">
            €{Float.round(@stats.cortexiq_total_commission, 2)}
          </div>
          <div class="text-xs text-yellow-400 mt-1">
            Platform commission
          </div>
        </div>

        <!-- Net Customer Savings -->
        <div class="bg-gradient-to-br from-blue-900 to-blue-800 rounded-lg p-4 border-2 border-blue-600">
          <div class="text-gray-300 text-xs">Customer Savings (Net)</div>
          <div class="text-3xl font-bold text-blue-300">
            €{Float.round(@stats.cortexiq_net_savings, 2)}
          </div>
          <div class="text-xs text-blue-400 mt-1">
            After commission
          </div>
        </div>

        <!-- ROI for Customers -->
        <div class="bg-gradient-to-br from-purple-900 to-purple-800 rounded-lg p-4 border-2 border-purple-600">
          <div class="text-gray-300 text-xs">Customer ROI</div>
          <% roi = if @stats.cortexiq_total_commission > 0, do: Float.round((@stats.cortexiq_net_savings / @stats.cortexiq_total_commission) * 100, 1), else: 0.0 %>
          <div class="text-3xl font-bold text-purple-300">
            {roi}%
          </div>
          <div class="text-xs text-purple-400 mt-1">
            Savings per € paid
          </div>
        </div>
      </div>
    </div>
    """
  end
end
