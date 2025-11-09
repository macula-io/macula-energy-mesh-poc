defmodule MaculaGatewayService.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_gateway_service,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MaculaGatewayService.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Embedded Gateway (Proprietary) - enables P2P mesh networking
      {:macula_gateway_ex, path: "../macula_gateway_ex", override: true}
    ]
  end
end
