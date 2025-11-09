defmodule MaculaGatewayService.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Get configuration from environment
    gateway_port = String.to_integer(System.get_env("MACULA_GATEWAY_PORT", "9443"))
    realm = System.get_env("MACULA_REALM", "be.cortexiq.energy")

    children = [
      # Start embedded Macula gateway for this city
      {MaculaGatewayEx,
       port: gateway_port, realm: realm, name: MaculaGatewayService.Gateway}
    ]

    opts = [strategy: :one_for_one, name: MaculaGatewayService.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
