defmodule CortexIqDashboard.DatabaseWriter.Consumer do
  @moduledoc """
  GenStage Consumer that receives batched events from the Flow pipeline
  and writes them to TimescaleDB using Ecto.

  This consumer performs batch inserts using Ecto.Repo.insert_all for optimal
  database performance. It handles errors gracefully and logs statistics.
  """
  use GenStage
  require Logger

  alias CortexIqDashboard.Repo
  alias CortexIqDashboard.Schemas.{EnergyEvent, EnergyTrade, ContractEvent}

  ## Client API

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  ## Server Callbacks

  @impl true
  def init(opts) do
    Logger.info("DatabaseWriter.Consumer: Starting consumer #{inspect(self())}")

    # Subscribe to the Flow with specific subscription options
    subscribe_to = Keyword.fetch!(opts, :subscribe_to)

    # Consumer subscribes to producer stages
    {:consumer, %{}, subscribe_to: subscribe_to}
  end

  @impl true
  def handle_events(events, _from, state) do
    # Process events in batch
    start_time = System.monotonic_time(:millisecond)

    # Group events by type
    grouped = Enum.group_by(events, &event_type/1)

    # Insert each type in batch
    results = %{
      energy: insert_energy_events(Map.get(grouped, :energy, [])),
      trade: insert_trade_events(Map.get(grouped, :trade, [])),
      contract: insert_contract_events(Map.get(grouped, :contract, []))
    }

    elapsed = System.monotonic_time(:millisecond) - start_time

    # Log statistics
    total_inserted = results.energy + results.trade + results.contract

    if total_inserted > 0 do
      Logger.info(
        "DatabaseWriter.Consumer: Inserted #{total_inserted} events in #{elapsed}ms " <>
          "(energy: #{results.energy}, trade: #{results.trade}, contract: #{results.contract})"
      )
    end

    {:noreply, [], state}
  end

  ## Private Functions

  defp event_type({:energy, _}), do: :energy
  defp event_type({:trade, _}), do: :trade
  defp event_type({:contract, _, _}), do: :contract

  defp insert_energy_events([]), do: 0

  defp insert_energy_events(events) do
    # Convert events to maps for insert_all
    records =
      events
      |> Enum.map(fn {:energy, data} -> EnergyEvent.from_wamp_event(data) end)
      |> Enum.reject(&is_nil/1)

    if length(records) > 0 do
      try do
        {count, _} = Repo.insert_all(EnergyEvent, records)
        count
      rescue
        e ->
          Logger.error("DatabaseWriter.Consumer: Failed to insert energy events: #{inspect(e)}")
          0
      end
    else
      0
    end
  end

  defp insert_trade_events([]), do: 0

  defp insert_trade_events(events) do
    # Convert events to maps for insert_all
    records =
      events
      |> Enum.map(fn {:trade, data} -> EnergyTrade.from_wamp_event(data) end)
      |> Enum.reject(&is_nil/1)

    if length(records) > 0 do
      try do
        {count, _} = Repo.insert_all(EnergyTrade, records)
        count
      rescue
        e ->
          Logger.error("DatabaseWriter.Consumer: Failed to insert trade events: #{inspect(e)}")
          0
      end
    else
      0
    end
  end

  defp insert_contract_events([]), do: 0

  defp insert_contract_events(events) do
    # Convert events to maps for insert_all
    records =
      events
      |> Enum.map(fn {:contract, event_type, data} ->
        ContractEvent.from_wamp_event(Atom.to_string(event_type), data)
      end)
      |> Enum.reject(&is_nil/1)

    if length(records) > 0 do
      try do
        {count, _} = Repo.insert_all(ContractEvent, records)
        count
      rescue
        e ->
          Logger.error("DatabaseWriter.Consumer: Failed to insert contract events: #{inspect(e)}")
          0
      end
    else
      0
    end
  end
end
