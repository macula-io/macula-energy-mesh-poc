defmodule CortexIqPrezio.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_prezio,
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
      mod: {CortexIqPrezio.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:macula_sdk, path: "../macula_sdk"},   # For WAMP publishing
      {:cortex_iq_core, path: "../cortex_iq_core"},  # For domain models
      {:req, "~> 0.5"}  # HTTP client for API calls
    ]
  end

  defp releases do
    [
      cortex_iq_prezio: [
        version: "0.1.0",
        applications: [cortex_iq_prezio: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
