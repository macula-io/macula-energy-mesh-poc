defmodule MaculaOs.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_os,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {MaculaOs.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.2"},
      {:websockex, "~> 0.4"},

      # Proxy server (localhost WebSocket)
      {:plug_cowboy, "~> 2.7"},
      {:websock_adapter, "~> 0.5"},

      # Metrics and telemetry
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"}
    ]
  end

  defp releases do
    [
      macula_os: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
