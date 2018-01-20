use Mix.Config

config :tonic_raft,
  log_adapter: TonicRaft.Log.InMemory

config :logger,
  level: :debug
