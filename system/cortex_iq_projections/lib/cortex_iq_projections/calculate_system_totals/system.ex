defmodule CortexIqProjections.CalculateSystemTotals.System do
  @moduledoc """
  Supervises the system totals calculation.

  This system manages:
  - One aggregator (subscribes to events via shared client, calculates totals, publishes results)

  ## Architecture

  Shared Macula Client → Aggregator (subscribes to home.measured)
                          ↓
                     Calculate totals every 500ms
                          ↓
                     Publish be.cortexiq.projections.totals_calculated
                          ↓
                     Store in database

  ## Strategy

  Uses `:one_for_one` strategy:
  - Aggregator uses shared client (QUIC multiplexing handles subscription)
  - If aggregator crashes, only aggregator restarts
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Use shared Macula client (QUIC multiplexing replaces dedicated client)
    client = Keyword.get(opts, :client, CortexIqProjections.MaculaClient)

    Logger.info("CalculateSystemTotals.System starting")
    Logger.info("  Using shared Macula client: #{inspect(client)}")

    children = [
      # Aggregator - subscribes to home.measured via shared client, calculates totals, publishes
      {CortexIqProjections.CalculateSystemTotals.Aggregator, [
        client: client
      ]}
    ]

    # one_for_one: aggregator crashes don't affect shared client
    Supervisor.init(children, strategy: :one_for_one)
  end
end
