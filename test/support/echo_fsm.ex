defmodule TonicRaft.Support.EchoFSM do
  @behaviour TonicRaft.StateMachine

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
