defmodule ExAdmin.Mixfile do
  use Mix.Project

  @version "0.9.0-dev"

  def project do
    [
      app: :ex_admin,
      version: @version,
      elixir: "~> 1.3",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: [:phoenix, :gettext] ++ Mix.compilers(),
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      name: "ExAdmin",
      docs: [extras: ["README.md"], main: "ExAdmin"],
      deps: deps(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      description: """
      An Elixir Phoenix Auto Administration Package.
      """
    ]
  end

  def application do
    [applications: applications(Mix.env())]
  end

  defp applications(:test) do
    [:plug, :cowboy, :ecto_sql | applications(:prod)]
  end

  defp applications(_) do
    [
      :csvlixir,
      :ecto,
      :ex_queb,
      :gettext,
      :inflex,
      :logger,
      :phoenix,
      :scrivener,
      :scrivener_ecto,
      :xain
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "web", "test/support"]
  defp elixirc_paths(_), do: ["lib", "web"]

  defp deps do
    [
      {:csvlixir, "~> 1.0.0"},
      {:credo, "~> 1.1"},
      {:decimal, "~> 1.0"},
      {:earmark, "~> 1.3.2", only: :dev},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:ex_doc, "~> 0.20.2", only: :dev},
      {:ex_queb, git: "https://github.com/tomjschuster/ex_queb", branch: "ecto_3"},
      {:exactor, "~> 2.2.0"},
      {:excoveralls, "~> 0.5", only: :test},
      {:floki, "~> 0.8", only: :test},
      {:gettext, "~> 0.11"},
      {:hound, "~> 1.0", only: :test},
      {:inflex, "~> 1.7"},
      {:phoenix, "~> 1.4"},
      {:phoenix_ecto, "~> 4.0"},
      {:phoenix_html, "~> 2.11"},
      {:plug_cowboy, "~> 2.0"},
      {:poison, "~> 3.0"},
      {:postgrex, "> 0.0.0", only: :test},
      {:scrivener_ecto, "~> 2.2"},
      {:xain, "== 0.6.1"}
    ]
  end

  defp package do
    [
      maintainers: ["Stephen Pallen", "Roman Smirnov"],
      licenses: ["MIT"],
      links: %{"Github" => "https://github.com/smpallen99/ex_admin"},
      files:
        ~w(lib priv web README.md package.json mix.exs LICENSE brunch-config.js AdminLte-LICENSE)
    ]
  end
end
