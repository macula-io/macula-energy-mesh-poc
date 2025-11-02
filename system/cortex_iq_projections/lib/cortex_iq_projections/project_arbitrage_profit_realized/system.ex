defmodule CortexIqProjections.ProjectArbitrageProfitRealized.System do
  @moduledoc """
  Supervises the complete vertical slice for projecting arbitrage.profit_realized events.

  Projects arbitrage.profit_realized events (battery arbitrage)

  ## Architecture

  WAMP Client → Subscriber → GenServer Projector → Database

  ## Strategy

  Uses `:rest_for_one` strategy for cascading restart behavior.
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

    # Unique WAMP client name for this event type
    wamp_client_name = :wamp_project_arbitrage_profit_realized

    Logger.info("ProjectArbitrageProfitRealized.System starting")
    Logger.info("  WAMP client: #{inspect(wamp_client_name)}")

    children = [
      # 1. WAMP Client
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

      # 2. Subscriber
      {CortexIqProjections.ProjectArbitrageProfitRealized.Subscriber, [
        wamp_client: wamp_client_name
      ]},

      # 3. GenServer Projector
      {CortexIqProjections.ProjectArbitrageProfitRealized.Projector, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
