defmodule CortexIqProjections.ProjectMarketContractSwitched.System do
  @moduledoc """
  Supervises the complete vertical slice for projecting market.contract_switched events.

  This system manages:
  - One dedicated WAMP client (for subscribing to market.contract_switched events)
  - One subscriber (receives events from WAMP)
  - One GenServer projector (updates home states, provider stats, and contract history)

  ## Architecture

  WAMP Client → Subscriber → GenServer Projector → Database

  ## Strategy

  Uses `:rest_for_one` strategy for cascading restart behavior.

  ## Why GenServer (not Broadway)?

  market.contract_switched is LOW-VOLUME (~50-100 switches/simulation day).
  Simple GenServer projector is sufficient - no batching needed.
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
    wamp_client_name = :wamp_project_market_contract_switched

    Logger.info("ProjectMarketContractSwitched.System starting")
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
      {CortexIqProjections.ProjectMarketContractSwitched.Subscriber, [
        wamp_client: wamp_client_name
      ]},

      # 3. GenServer Projector
      {CortexIqProjections.ProjectMarketContractSwitched.Projector, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
