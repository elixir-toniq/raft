defmodule TonicLeader.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tonic_leader,
      version: "0.1.0",
      elixir: "~> 1.5",
      elixirc_paths: elixirc_paths(Mix.env),
      start_permanent: Mix.env == :prod,
      deps: deps(),
      name: "TonicLeader",
      description: description(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TonicLeader.Application, []}
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(:dev), do: ["lib", "test/support/generators.ex"]
  def elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps, do: [
    {:gen_state_machine, "~> 2.0"},
    {:rocksdb, "~> 0.13.1"},
    {:jason, "~> 1.0-rc"},
    {:msgpax, "~> 2.0"},
    {:dialyxir, "~> 0.5", only: :dev},
    {:stream_data, "~> 0.4", only: [:dev, :test]},
  ]

  defp description do
    """
    An leader election, and concensus protocol based on Raft.
    """
  end
end
