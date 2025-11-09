defmodule MaculaGatewayEx.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # No children by default - gateway is started explicitly by applications
    ]

    opts = [strategy: :one_for_one, name: MaculaGatewayEx.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
