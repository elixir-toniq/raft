defmodule Raft.PeerSupervisor do
  use Supervisor

  def start_link({name, config}) do
    Supervisor.start_link(__MODULE__, {name, config}, name: sup_name(name))
  end

  @spec sup_name(Raft.peer()) :: String.t
  def sup_name({name, _}) do
    sup_name(name)
  end
  def sup_name(name) do
    :"#{name}_sup"
  end

  def init({name, config}) do
    children = [
      {Raft.Log, [name, config]},
      {Raft.Server, {name, config}},
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
