defmodule CortexIqSimulation.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_simulation,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp releases do
    [
      cortex_iq_simulation: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CortexIqSimulation.Application, []},
      # Don't auto-start MaculaOs.Application (we only need the WAMP client modules)
      included_applications: [:macula_os]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:macula_os, path: "../macula_os"}
    ]
  end
end
