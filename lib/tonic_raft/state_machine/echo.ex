defmodule Raft.StateMachine.Echo do
  @behaviour Raft.StateMachine

  def init(_), do: :ok

  def handle_write(op, state), do: {op, state}

  def handle_read(op, state), do: {op, state}
end
