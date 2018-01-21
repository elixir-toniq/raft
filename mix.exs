defmodule TonicRaft.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tonic_raft,
      version: "0.1.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env),
      start_permanent: Mix.env == :prod,
      deps: deps(),
      name: "TonicRaft",
      description: description(),
      dialyzer: [
        plt_add_deps: :transitive,
      ],
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TonicRaft.Application, []}
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(:dev), do: ["lib", "test/support/generators.ex"]
  def elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps, do: [
    {:gen_state_machine, git: "https://github.com/keathley/gen_state_machine"},
    {:rocksdb, "~> 0.13.1"},
    {:jason, "~> 1.0-rc"},
    {:msgpax, "~> 2.0"},
    {:uuid, "~> 1.1"},
    {:dialyxir, "~> 0.5", only: :dev, runtime: false},
    {:stream_data, "~> 0.4", only: [:dev, :test]},
  ]

  defp description do
    """
    An leader election, and concensus protocol based on Raft.
    """
  end
end
