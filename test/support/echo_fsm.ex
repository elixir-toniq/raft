defmodule Raft.Support.EchoFSM do
  @behaviour Raft.StateMachine

  def init(_) do
    :ok
  end

  def handle_write(cmd, state) do
    {{:ok, cmd}, state}
  end

  def handle_read(cmd, state) do
    {{:ok, cmd}, state}
  end
end
