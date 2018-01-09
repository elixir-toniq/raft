use Mix.Config

config :tonic_leader,
  log_adapter: TonicLeader.Log.InMemory

config :logger,
  level: :debug
