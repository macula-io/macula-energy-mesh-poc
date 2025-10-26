defmodule CortexIqProjections.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_projections,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {CortexIqProjections.Application, []},
      included_applications: [:macula_os]  # Don't auto-start MaculaOs proxy
    ]
  end

  defp deps do
    [
      {:cortex_iq_dashboard_schemas, path: "../cortex_iq_dashboard_schemas"},  # Shared schemas
      {:macula_os, path: "../macula_os"},   # For WAMP client
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
      cortex_iq_projections: [
        version: "0.1.0",
        applications: [cortex_iq_projections: :permanent],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
