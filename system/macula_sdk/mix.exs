defmodule MaculaSdk.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_sdk,
      version: "0.2.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir SDK for Macula Platform - HTTP/3 Transport",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Erlang macula_sdk - the actual HTTP/3 SDK implementation
      # Fetched from GitHub macula repository
      # Using different atom name to avoid circular dependency
      {:macula_sdk_erl,
        git: "git@github.com:macula-io/macula.git",
        branch: "main",
        sparse: "apps/macula_sdk",
        app: false,
        compile: "rebar3 compile",
        manager: :rebar3,
        override: true}
    ]
  end

  defp package do
    [
      name: "macula_sdk",
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/macula-io/macula",
        "Docs" => "https://docs.macula.io"
      }
    ]
  end
end
