defmodule Raft.StateMachine.Echo do
  @moduledoc """
  A simple state machine that simply echos commands.
  """ && false

  @behaviour Raft.StateMachine

  def init(_), do: :ok

  def handle_write(op, state), do: {op, state}

  def handle_read(op, state), do: {op, state}
end
