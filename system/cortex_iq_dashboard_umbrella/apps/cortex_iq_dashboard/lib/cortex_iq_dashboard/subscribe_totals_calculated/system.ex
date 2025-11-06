defmodule CortexIqDashboard.SubscribeTotalsCalculated.System do
  @moduledoc """
  Supervises the totals_calculated subscription vertical slice.

  This system manages:
  - One dedicated WAMP client (for subscribing to projections.totals_calculated)
  - One subscriber (receives calculated totals, broadcasts to LiveView)

  ## Architecture

  WAMP Client → Subscriber → Phoenix.PubSub (dashboard:totals_calculated) → OverviewLive

  ## Strategy

  Uses `:rest_for_one` strategy:
  - WAMP client starts first
  - Subscriber starts second, using the client
  - If WAMP client crashes, subscriber restarts too
  - If subscriber crashes, only subscriber restarts
  """
  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Use shared WAMP pool instead of dedicated client
    pool_name = Keyword.get(opts, :pool_name, CortexIqDashboard.WampPool)

    Logger.info("SubscribeTotalsCalculated.System starting")
    Logger.info("  Using shared WAMP pool: #{inspect(pool_name)}")

    children = [
      # Subscriber - subscribes to be.cortexiq.projections.totals_calculated via pool
      {CortexIqDashboard.SubscribeTotalsCalculated.Subscriber, [
        pool_name: pool_name
      ]}
    ]

    # one_for_one: subscriber crashes don't affect pool
    Supervisor.init(children, strategy: :one_for_one)
  end
end
