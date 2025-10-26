defmodule CortexIqDashboardSchemas.MixProject do
  use Mix.Project

  def project do
    [
      app: :cortex_iq_dashboard_schemas,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:postgrex, ">= 0.0.0"}
    ]
  end
end
