defmodule CortexIqDashboardWeb.Components.PlatformCharts do
  @moduledoc """
  LiveComponent for platform-wide KPI charts.

  Displays time-series charts for:
  - Connected Homes Over Time
  - Production vs Consumption Over Time
  - Contract Switches Over Time (Cumulative)
  - Financial Performance Over Time (Savings & Commission)
  """
  use CortexIqDashboardWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <%= if has_sufficient_data?(@aggregate_history) do %>
        <div>
          <h2 class="text-2xl font-bold mb-4 text-gray-100">Platform Performance Over Time</h2>

          <div class="grid grid-cols-2 gap-6">
            <!-- Connected Homes Over Time -->
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h3 class="text-lg font-semibold text-gray-300 mb-4">Connected Homes</h3>
              <div
                id="connected-homes-chart"
                phx-hook="ConnectedHomesChart"
                phx-update="ignore"
                data-history={Jason.encode!(@aggregate_history)}
              >
              </div>
            </div>

            <!-- Production vs Consumption Over Time -->
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h3 class="text-lg font-semibold text-gray-300 mb-4">Production vs Consumption</h3>
              <div
                id="aggregate-power-chart"
                phx-hook="AggregatePowerChart"
                phx-update="ignore"
                data-history={Jason.encode!(@aggregate_history)}
              >
              </div>
            </div>

            <!-- Contract Switches Over Time (Cumulative) -->
            <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
              <h3 class="text-lg font-semibold text-gray-300 mb-4">Contract Switches (Cumulative)</h3>
              <div
                id="contract-switches-chart"
                phx-hook="ContractSwitchesChart"
                phx-update="ignore"
                data-history={Jason.encode!(@aggregate_history)}
              >
              </div>
            </div>

            <!-- Financial Performance Over Time -->
            <%= if length(@overview.savings_history || []) > 0 do %>
              <div class="bg-gray-800 rounded-lg p-6 border border-gray-700">
                <h3 class="text-lg font-semibold text-gray-300 mb-4">Financial Performance</h3>
                <div
                  id="savings-history-chart"
                  phx-hook="SavingsHistoryChart"
                  phx-update="ignore"
                  data-savings-history={Jason.encode!(@overview.savings_history)}
                >
                </div>
              </div>
            <% end %>
          </div>
        </div>
      <% else %>
        <!-- Placeholder when no data -->
        <div class="bg-gray-800 rounded-lg p-8 border border-gray-700 text-center">
          <div class="text-gray-400 text-lg">
            📊 Platform performance charts will appear once sufficient data is collected.
          </div>
          <div class="text-gray-500 text-sm mt-2">
            Charts require at least 5 data points for visualization.
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Helper functions

  defp has_sufficient_data?(history) when is_list(history) do
    length(history) >= 5
  end
  defp has_sufficient_data?(_), do: false
end
