defmodule Ownet.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/oooska/ownet"

  def project do
    [
      app: :ownet,
      version: @version,
      elixir: "~> 1.14",
      name: "Ownet",
      source_url: @source_url,
      description: "An OWFS / owserver 1-wire client library",
      docs: docs(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package()
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
      extras: ["README.md"],
      source_url: @source_url,
      source_ref: "v#{@version}"
    ]
  end

  defp package() do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
