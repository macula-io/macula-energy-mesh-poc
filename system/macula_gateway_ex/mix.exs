defmodule MaculaGatewayEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_gateway_ex,
      version: "0.2.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir wrapper for embedded Macula Gateway - P2P Mesh Networking (Proprietary)"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MaculaGatewayEx.Application, []}
    ]
  end

  defp deps do
    [
      # Private Erlang packages - local development uses path dependencies
      # In production, these would come from GitHub (requires repo access)
      {:macula_gateway, path: "/home/rl/work/github.com/macula-io/macula/apps/macula_gateway", manager: :rebar3, override: true},
      {:macula_pubsub, path: "/home/rl/work/github.com/macula-io/macula/apps/macula_pubsub", manager: :rebar3, override: true},
      {:macula_rpc, path: "/home/rl/work/github.com/macula-io/macula/apps/macula_rpc", manager: :rebar3, override: true},
      {:macula_topology, path: "/home/rl/work/github.com/macula-io/macula/apps/macula_topology", manager: :rebar3, override: true}
    ]
  end
end
