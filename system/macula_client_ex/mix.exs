defmodule MaculaClientEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_client_ex,
      version: "0.2.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for Macula Platform - HTTP/3 Transport (Free, Open Source)",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :macula_sdk]
    ]
  end

  defp deps do
    [
      # Erlang macula_sdk - the actual HTTP/3 SDK implementation
      # Published on Hex.pm - free, open source
      {:macula_sdk, "~> 0.2.0", manager: :rebar3, override: true}
    ]
  end

  defp package do
    [
      name: "macula_client_ex",
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => "https://github.com/macula-io/macula",
        "Docs" => "https://docs.macula.io"
      }
    ]
  end
end
