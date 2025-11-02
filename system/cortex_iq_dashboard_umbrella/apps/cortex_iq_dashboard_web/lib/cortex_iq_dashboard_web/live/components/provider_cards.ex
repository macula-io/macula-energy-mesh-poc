defmodule CortexIqDashboardWeb.Components.ProviderCards do
  @moduledoc """
  LiveComponent for energy provider cards grid.

  Displays 5 provider cards showing:
  - Provider name
  - Market share percentage
  - Number of contracts
  - Provider strategy
  """
  use CortexIqDashboardWeb, :live_component

  @provider_names %{
    "provider_a" => "Essent",
    "provider_b" => "Eneco",
    "provider_c" => "Vattenfall",
    "provider_d" => "Greenchoice",
    "provider_e" => "Budget Energie"
  }

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mb-6">
      <h3 class="text-sm font-semibold text-gray-400 mb-3">Energy Providers - Market Competition</h3>
      <div class="grid grid-cols-5 gap-4">
        <%= for provider_id <- ["provider_a", "provider_b", "provider_c", "provider_d", "provider_e"] do %>
          <% provider_state = Map.get(@provider_states, provider_id, %{}) %>
          <% market_share = Map.get(@provider_market_share, provider_id, 0) %>
          <% total_homes = @total_homes %>
          <% share_percent = if total_homes > 0, do: Float.round(market_share / total_homes * 100, 1), else: 0.0 %>
          <button
            phx-click="select_provider"
            phx-value-provider_id={provider_id}
            phx-target={@myself}
            class={"bg-gray-800 rounded-lg p-4 border-2 transition-all hover:border-yellow-500 #{if @selected_provider == provider_id, do: "border-yellow-500", else: "border-gray-700"}"}
          >
            <div class="text-left">
              <div class="text-sm font-bold text-yellow-400">
                {get_provider_name(provider_id)}
              </div>
              <div class="mt-2">
                <div class="text-xs text-gray-400">Market Share</div>
                <div class="text-2xl font-bold text-white">
                  {share_percent}%
                </div>
                <div class="text-xs text-gray-500">{market_share} contracts</div>
              </div>
              <%= if Map.get(provider_state, :strategy) do %>
                <div class="text-xs text-gray-400 mt-2 truncate">
                  {format_strategy(Map.get(provider_state, :strategy))}
                </div>
              <% end %>
            </div>
          </button>
        <% end %>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("select_provider", %{"provider_id" => provider_id}, socket) do
    send(self(), {:select_provider, provider_id})
    {:noreply, socket}
  end

  # Helper functions

  defp get_provider_name(provider_id) do
    Map.get(@provider_names, provider_id, provider_id)
  end

  defp format_strategy(strategy) when is_binary(strategy) do
    strategy
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
  defp format_strategy(_), do: ""
end
