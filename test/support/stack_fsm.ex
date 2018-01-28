defmodule TonicRaft.Support.StackFSM do
  @behaviour TonicRaft.StateMachine

  def init(_) do
    []
  end

  def handle_read(:length, stack) do
    {Enum.count(stack), stack}
  end

  def handle_read(:all, stack) do
    {stack, stack}
  end

  def handle_write({:enqueue, item}, stack) do
    new_stack = [item | stack]
    {Enum.count(new_stack), new_stack}
  end

  def handle_write(:dequeue, [item | stack]) do
    {item, stack}
  end

  def handle_write(:dequeue, []) do
    {:empty, []}
  end
end
