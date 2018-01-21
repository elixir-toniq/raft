defmodule TonicRaft.PeerSupervisor do
  use Supervisor

  def start_link({name, config}) do
    Supervisor.start_link(__MODULE__, {name, config}, name: :"#{name}_sup")
  end

  def init({name, config}) do
    children = [
      {TonicRaft.Log, [name, config]},
      {TonicRaft.Server, {name, config}},
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
