defmodule MaculaClientEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :macula_client_ex,
      version: "0.3.4",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Elixir client for Macula Platform - HTTP/3 Transport (Free, Open Source)",
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
      # Consolidated Macula platform package - includes all modules
      # Published on Hex.pm - free, open source
      {:macula, "~> 0.3.4"},

      # Documentation
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
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
