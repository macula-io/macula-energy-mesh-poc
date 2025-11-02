defmodule CortexIqProjections.ProjectMarketContractSwitched.Projector do
  @moduledoc """
  GenServer projector for market.contract_switched events.

  ## Performance

  - Input rate: ~50-100 switches/simulation day (very low volume)
  - No batching needed - simple synchronous database writes
  - Updates multiple tables per event:
    - home_states (update contract info)
    - provider_states (decrement/increment active_contracts)
    - system_stats (increment contract_switches_count)
    - contract_events (insert new row)

  ## Event Structure

  ```elixir
  %{
    kwargs: %{
      "home_id" => "019a...",
      "from_contract_id" => "contract_abc",
      "from_provider_id" => "provider_b",
      "to_contract_id" => "contract_xyz",
      "to_provider_id" => "provider_a",
      "reason" => "balance_optimization",
      "projected_savings" => 45.50,
      "days_before_expiry" => 180,
      "discount_received" => 25.00,
      "simulation_time" => "2025-01-15T14:32:00Z",
      "terms" => %{
        "day_buy_price" => 0.15,
        "night_buy_price" => 0.08,
        ...
      }
    }
  }
  ```
  """
  use GenServer
  require Logger
  import Ecto.Query
  import Ecto.Query.API, only: [fragment: 1]
  alias CortexIqProjections.Repo
  alias CortexIqDashboardSchemas.Projections.{HomeState, ProviderState, SystemStats}
  alias CortexIqDashboardSchemas.TimeSeries.ContractEvent

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def project_event(event_data) do
    GenServer.cast(__MODULE__, {:project, event_data})
  end

  # GenServer Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ProjectMarketContractSwitched.Projector: Started")
    {:ok, %{}}
  end

  @impl true
  def handle_cast({:project, event_data}, state) do
    project_contract_switched(event_data)
    {:noreply, state}
  end

  # Projection Logic

  defp project_contract_switched(event_data) do
    kwargs = Map.get(event_data, :kwargs, %{})

    home_id = kwargs["home_id"]
    from_provider_id = kwargs["from_provider_id"]
    to_provider_id = kwargs["to_provider_id"]
    to_contract_id = kwargs["to_contract_id"]
    simulation_time = parse_datetime(kwargs["simulation_time"])

    # 1. Update home_states with new contract
    Repo.insert!(
      %HomeState{home_id: home_id},
      on_conflict: [
        set: [
          provider_id: to_provider_id,
          contract_id: to_contract_id,
          contract_expires_at: parse_datetime(kwargs["contract_end_date"]),
          last_event_at: simulation_time,
          updated_at: DateTime.utc_now()
        ]
      ],
      conflict_target: :home_id
    )

    # 2. Decrement active_contracts for old provider
    if from_provider_id do
      from(p in ProviderState, where: p.provider_id == ^from_provider_id)
      |> Repo.update_all(
        set: [
          active_contracts: fragment("GREATEST(0, active_contracts - 1)"),
          updated_at: DateTime.utc_now()
        ]
      )
    end

    # 3. Increment active_contracts for new provider
    case from(p in ProviderState, where: p.provider_id == ^to_provider_id)
         |> Repo.update_all(inc: [active_contracts: 1], set: [updated_at: DateTime.utc_now()]) do
      {0, _} ->
        # Provider doesn't exist yet, create it
        Repo.insert!(
          %ProviderState{provider_id: to_provider_id, active_contracts: 1},
          on_conflict: :nothing,
          conflict_target: :provider_id
        )
      _ -> :ok
    end

    # 4. Increment global contract switches count
    from(s in SystemStats, where: s.id == 1)
    |> Repo.update_all(inc: [contract_switches_count: 1], set: [updated_at: DateTime.utc_now()])

    # 5. Insert contract event record
    terms = kwargs["terms"] || %{}

    Repo.insert!(%ContractEvent{
      contract_id: to_contract_id,
      home_id: home_id,
      provider_id: to_provider_id,
      event_type: "switch",
      simulation_time: simulation_time,
      previous_contract_id: kwargs["from_contract_id"],
      previous_provider_id: from_provider_id,
      switch_reason: kwargs["reason"],
      projected_savings: kwargs["projected_savings"],
      days_before_expiry: kwargs["days_before_expiry"],
      day_buy_price: terms["day_buy_price"],
      night_buy_price: terms["night_buy_price"],
      day_sell_price: terms["day_sell_price"],
      night_sell_price: terms["night_sell_price"],
      switching_discount: terms["switching_discount"]
    })
  rescue
    error ->
      Logger.error("ProjectMarketContractSwitched.Projector: Error: #{inspect(error)}")
      Logger.error("Event data: #{inspect(event_data)}")
  end

  # Helper Functions

  defp parse_datetime(nil), do: nil

  defp parse_datetime(dt) when is_binary(dt) do
    case DateTime.from_iso8601(dt) do
      {:ok, datetime, _offset} -> datetime
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = dt), do: dt
end
