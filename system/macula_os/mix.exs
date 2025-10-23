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
      {:cortex_iq_core, path: "../cortex_iq_core"},
      {:jason, "~> 1.2"},
      {:websockex, "~> 0.4"}
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
