defmodule TonicRaft.Server.Supervisor do
  @moduledoc """
  Manages Server processes.
  """
  use DynamicSupervisor

  alias TonicRaft.PeerSupervisor

  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def start_peer(name, config) do
    DynamicSupervisor.start_child(__MODULE__, {PeerSupervisor, {name, config}})
  end

  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
