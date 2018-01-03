defmodule TonicLeader.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      TonicLeader.Log.InMemory,
      TonicLeader.Server.Supervisor,
    ]

    opts = [strategy: :one_for_one, name: TonicLeader.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
