defmodule CatalystPlugins.MixProject do
  use Mix.Project

  @app :catalyst_plugins
  @name "Catalyst Plugins"
  @version "0.1.0"
  @github "https://github.com/catalyst-ex/catalyst-plugins"

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.19",
      description: description(),
      package: package(),
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),
      name: @name,
      source_url: @github,
      homepage_url: @github,
      docs: [
        main: @name,
        canonical: "https://hexdocs.pm/#{@app}",
        extras: ["README.md"]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:catalyst, path: "../catalyst"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      quality: ["format", "credo", "sobelow --exit low"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp description do
    "Official plugins for Catalyst"
  end

  defp package do
    [
      name: @app,
      maintainers: ["Sheharyar Naseer", "Mudassar Ali", "Rana Tallal Ahmad"],
      licenses: ~w[MIT],
      files: ~w(mix.exs lib priv README.md),
      links: %{"GitHub" => @github}
    ]
  end
end
