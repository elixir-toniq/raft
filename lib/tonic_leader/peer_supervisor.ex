defmodule TonicLeader.PeerSupervisor do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def init(_arg) do
    children = [
      {TonicLeader.LogServer, []},
      {TonicLeader.Server, []},
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
