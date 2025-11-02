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
    bondy_url = Keyword.get(opts, :bondy_url, System.get_env("BONDY_URL", "ws://localhost:18080/ws"))
    realm_uri = Keyword.get(opts, :realm_uri, System.get_env("BONDY_REALM", "be.cortexiq.energy"))

    # Unique WAMP client name for this subscription
    wamp_client_name = :wamp_subscribe_totals_calculated

    Logger.info("SubscribeTotalsCalculated.System starting")
    Logger.info("  WAMP client: #{inspect(wamp_client_name)}")
    Logger.info("  Bondy URL: #{bondy_url}")
    Logger.info("  Realm: #{realm_uri}")

    children = [
      # 1. WAMP Client - dedicated connection
      %{
        id: wamp_client_name,
        start: {MaculaSdk.Wamp, :start_link, [[
          url: bondy_url,
          realm: realm_uri,
          name: wamp_client_name
        ]]},
        type: :worker,
        restart: :permanent,
        shutdown: 5000
      },

      # 2. Subscriber - subscribes to be.cortexiq.projections.totals_calculated
      {CortexIqDashboard.SubscribeTotalsCalculated.Subscriber, [
        wamp_client: wamp_client_name
      ]}
    ]

    # rest_for_one: if WAMP crashes, subscriber restarts too
    Supervisor.init(children, strategy: :rest_for_one)
  end
end
