defmodule CortexIqProjections.RegisterHome.System do
  @moduledoc """
  Vertical slice system for register_home RPC procedure.

  Supervision tree:
  - WAMP Client (unique to this slice)
  - RPC Handler (registers and handles the procedure)
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("RegisterHome.System: Starting register_home vertical slice")

    children = [
      # RPC handler that registers the procedure
      CortexIqProjections.RegisterHome.RpcHandler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
