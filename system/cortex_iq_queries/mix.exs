defmodule CortexIqQueries.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_queries,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {CortexIqQueries.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:cortex_iq_dashboard_schemas, path: "../cortex_iq_dashboard_schemas"},  # Shared schemas
      {:macula_sdk,
        git: "git@github.com:macula-io/macula-energy-mesh-poc.git",
        branch: "feature/competition",
        sparse: "system/macula_sdk",
        override: true},   # For RPC server (HTTP/3)
      {:cortex_iq_core, path: "../cortex_iq_core"},  # For domain models
      {:ecto_sql, "~> 3.12"},  # Database toolkit
      {:postgrex, ">= 0.0.0"}  # PostgreSQL driver
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp releases do
    [
      cortex_iq_queries: [
        version: "0.1.0",
        applications: [cortex_iq_queries: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
