defmodule Raft.Server.Supervisor do
  @moduledoc """
  Manages Server processes.
  """ && false

  use DynamicSupervisor

  alias Raft.PeerSupervisor

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def start_peer(name, config) do
    DynamicSupervisor.start_child(__MODULE__, {PeerSupervisor, {name, config}})
  end

  def stop_peer(name) do
    require Logger
    Logger.info("#{PeerSupervisor.sup_name(name)}: Shutting down")

    pid =
      name
      |> PeerSupervisor.sup_name
      |> Process.whereis

    children = DynamicSupervisor.which_children(__MODULE__)

    if pid do
      case List.keyfind(children, pid, 1) do
        nil ->
          # This was not started via `start_peer`, tell the supervisor
          # to shut itself down instead
          Supervisor.stop(pid)

        _child ->
          DynamicSupervisor.terminate_child(__MODULE__, pid)
      end
    else
      {:error, :no_peer}
    end
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
