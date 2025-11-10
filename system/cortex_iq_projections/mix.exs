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
      mod: {CortexIqProjections.Application, []}
    ]
  end

  defp deps do
    [
      {:cortex_iq_dashboard_schemas, path: "../cortex_iq_dashboard_schemas"},  # Shared schemas
      # Client library (Free, Open Source) - connects to standalone gateway
      {:macula, "~> 0.3.4"},
      {:cortex_iq_core, path: "../cortex_iq_core"},  # For domain models
      {:ecto_sql, "~> 3.12"},  # Database toolkit
      {:postgrex, ">= 0.0.0"},  # PostgreSQL driver
      {:broadway, "~> 1.1"}  # For high-throughput event processing with back-pressure
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
        steps: [:assemble, &copy_migrations/1, :tar]
      ]
    ]
  end

  # Copy migrations from cortex_iq_dashboard_schemas dependency into release
  defp copy_migrations(release) do
    migrations_source = Path.join([:code.priv_dir(:cortex_iq_dashboard_schemas), "repo", "migrations"])
    migrations_dest = Path.join([release.path, "lib", "cortex_iq_dashboard_schemas-#{Application.spec(:cortex_iq_dashboard_schemas, :vsn)}", "priv", "repo", "migrations"])

    File.mkdir_p!(migrations_dest)
    File.cp_r!(migrations_source, migrations_dest)

    release
  end
end
