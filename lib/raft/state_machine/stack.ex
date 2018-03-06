defmodule Raft.StateMachine.Stack do
  @moduledoc """
  An example of a stack state machine
  """ && false

  @behaviour Raft.StateMachine

  def init(_) do
    []
  end

  def handle_read(:length, stack) do
    {{:ok, Enum.count(stack)}, stack}
  end

  def handle_read(:all, stack) do
    {{:ok, stack}, stack}
  end

  def handle_write({:put, item}, stack) do
    new_stack = [item | stack]
    {{:ok, Enum.count(new_stack)}, new_stack}
  end

  def handle_write(:pop, [item | stack]) do
    {{:ok, item}, stack}
  end

  def handle_write(:pop, []) do
    {{:ok, :empty}, []}
  end
end
