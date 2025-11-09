defmodule MaculaSdk.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_sdk,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # WAMP client dependencies
      {:jason, "~> 1.2"},
      {:websockex, "~> 0.4"},

      # Connection pooling
      {:poolboy, "~> 1.5"},

      # Metrics and telemetry
      {:telemetry, "~> 1.0"}
    ]
  end
end
