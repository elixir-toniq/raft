defmodule TonicLeader.Server.Supervisor do
  @moduledoc """
  Manages Server processes.
  """
  use Supervisor

  alias TonicLeader.Server

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  def start_peer(name, config) do
    Supervisor.start_child(__MODULE__, [name, config])
  end

  def start_server(config) do
    Supervisor.start_child(__MODULE__, [config])
  end
  def init(_arg) do
    child = Supervisor.child_spec(Server, start: {Server, :start_link, []})

    Supervisor.init([child], [strategy: :simple_one_for_one])
  end
end
