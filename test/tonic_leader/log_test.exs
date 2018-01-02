defmodule TonicLeader.LogTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import TonicLeader.Generators

  alias TonicLeader.Log
  alias TonicLeader.Log.Entry

  test "append/2 sets the commit index" do
    entry = %Entry{index: 1, term: 2, data: :foo, type: :command}
    log = Log.append(%Log{}, entry)

    assert log.commit_index == 1
  end

  test "append/2 adds the new entry" do
    entry = %Entry{index: 1, term: 2, data: :foo, type: :command}
    log = Log.append(%Log{}, entry)

    assert log.entries[1] == entry
  end

  describe "entries_from_index/2" do
    property "returns all entries greater then or equal to the given index" do
      # TODO This should actually generate a "old entries", an index, and "new
      # entries". The "new entries" should all have indexes greater then or equal
      # to the index. That way we can just append all of the logs and then check
      # to make sure that our slicing only retrieves new logs.
      # This is a better approach then duplicating the actual code like I am here.
      check all entries <- entries(),
                index   <- positive_integer() do
        log = Enum.reduce(entries, Log.new(), & Log.append(&2, &1))

        assert Log.entries_from_index(log, index) == Enum.filter(entries, & &1.index >= index)
      end
    end
  end
end
