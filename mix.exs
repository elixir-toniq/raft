defmodule TonicLeader.Mixfile do
  use Mix.Project

  def project do
    [
      app: :tonic_leader,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TonicLeader.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps, do: [
    {:gen_state_machine, "~> 2.0"},
  ]
end
