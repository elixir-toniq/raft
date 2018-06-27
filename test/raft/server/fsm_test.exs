defmodule Raft.Server.FSMTest do
  use ExUnit.Case, async: true

  alias Raft.Server.FSM

  describe "leader receives write request" do
    test "resets timeout" do
      # {:leader, data, actions} = FSM.next(:leader, old_data)
      # assert actions == [
      #   AppendEntry
      # ]
    end

    test "writes entry to the log" do

    end

    test "index is increased" do

    end

    test "append entries are sent to the other servers" do

    end

    test "resets match index" do

    end

    test "stays in leader state" do

    end
  end
end
