defmodule Raft.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @maintainers [
    "Chris Keathley"
  ]

  def project do
    [
      name: "Raft",
      app: :raft,
      version: @version,
      elixir: "~> 1.6",
      elixirc_paths: elixirc_paths(Mix.env),
      start_permanent: Mix.env == :prod,

      deps: deps(),
      description: description(),
      package: package(),

      dialyzer: [
        plt_add_deps: :transitive,
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Raft.Application, []}
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(:dev), do: ["lib", "test/support/generators.ex"]
  def elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps, do: [
    {:gen_state_machine, "~> 2.0"},
    {:rocksdb, "~> 0.13.1"},
    {:uuid, "~> 1.1"},
    {:dialyxir, "~> 0.5", only: :dev, runtime: false},
    {:stream_data, "~> 0.4", only: [:dev, :test]},
    {:propcheck, "~> 1.0", only: [:test]},
    {:ex_doc, "~> 0.16", only: :dev},
  ]

  defp description do
    """
    An implementation of the raft consensus protocol. Provides a way to create
    strongly consistent, distributed state machines.
    """
  end

  defp package do
    [
      name: :raft,
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: @maintainers,
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/keathley/raft"},
    ]
  end
end
