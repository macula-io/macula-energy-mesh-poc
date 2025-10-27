defmodule CortexIqUtilities.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_utilities,
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
      mod: {CortexIqUtilities.Application, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cortex_iq_core, path: "../cortex_iq_core"},
      {:macula_sdk, path: "../macula_sdk"}
    ]
  end

  defp releases do
    [
      cortex_iq_utilities: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
