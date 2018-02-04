defmodule Raft.StateMachine.Stack do
  @behaviour Raft.StateMachine

  def init(_) do
    []
  end

  def handle_read(:length, stack) do
    {Enum.count(stack), stack}
  end

  def handle_read(:all, stack) do
    {stack, stack}
  end

  def handle_write({:put, item}, stack) do
    new_stack = [item | stack]
    {Enum.count(new_stack), new_stack}
  end

  def handle_write(:pop, [item | stack]) do
    {item, stack}
  end

  def handle_write(:pop, []) do
    {:empty, []}
  end
end
