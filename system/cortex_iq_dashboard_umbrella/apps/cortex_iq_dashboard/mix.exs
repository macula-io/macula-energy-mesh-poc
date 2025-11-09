defmodule CortexIqDashboard.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_dashboard,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {CortexIqDashboard.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:cortex_iq_core, path: "../../../cortex_iq_core"},
      {:cortex_iq_dashboard_schemas, path: "../../../cortex_iq_dashboard_schemas"},
      {:macula_sdk,
        git: "git@github.com:macula-io/macula-energy-mesh-poc.git",
        branch: "feature/competition",
        sparse: "system/macula_sdk",
        override: true},
      {:dns_cluster, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.2"},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
