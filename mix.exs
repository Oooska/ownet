defmodule Ownet.MixProject do
  use Mix.Project

  def project do
    [
      app: :ownet,
      version: "0.1.0",
      elixir: "~> 1.14",
      name: "Ownet",
      source_url: "https://github.com/oooska/ownet",
      description: "An OWFS/owserver client library",
      docs: &docs/0,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    []
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:mox, "~> 1.0.2", only: :test},
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false, warn_if_outdated: true}
    ]
  end

  defp docs() do
    [
      main: "readme",
      extras: ["README.md"]
    ]
  end
end
