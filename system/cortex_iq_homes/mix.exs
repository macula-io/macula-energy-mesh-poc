defmodule CortexIqHomes.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_homes,
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
      mod: {CortexIqHomes.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cortex_iq_core, path: "../cortex_iq_core"},
      # Client library (Free, Open Source) - connects to standalone gateway
      {:macula_client_ex, path: "../macula_client_ex", override: true},
      {:phoenix_pubsub, "~> 2.1"}
    ]
  end

  defp releases do
    [
      cortex_iq_homes: [
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
