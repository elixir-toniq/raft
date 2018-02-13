defmodule Raft.StateMachineTest do
  use ExUnit.Case, async: false

  defmodule TestStateMachine do
    use Raft.StateMachine

    def init(_name) do
      {:ok, :ok}
    end

    def handle_write(msg, state) do
      {{:ok, msg}, state}
    end

    def handle_read(msg, state) do
      {{:ok, msg}, state}
    end

    def name, do: :s1
  end

  test "defines child_spec/1" do
    assert TestStateMachine.child_spec([]) == %{
      id: TestStateMachine,
      start: {TestStateMachine, :start_link, [[]]},
      type: :supervisor,
    }
  end

  describe "write/2" do
    setup do
      {:ok, _pid} = TestStateMachine.start_link(%Raft.Config{})

      on_exit fn ->
        TestStateMachine.stop()
      end
    end

    test "handles any leader redirections" do
      assert {:ok, "set key val"} = TestStateMachine.write("set key val")
    end

    @tag :skip
    test "allows options" do
      flunk "Not implemented"
    end
  end

  describe "read/2" do
    @tag :skip
    test "handles any leader redirections" do
      flunk "Not implemented"
    end

    @tag :skip
    test "allows options" do
      flunk "Not implemented"
    end
  end
end
