defmodule TonicLeader.Generators do
  import StreamData
  import ExUnitProperties

  alias TonicLeader.Log.Entry

  def entries do
    list_of(entry())
  end

  def entry do
    gen all index <- positive_integer(),
            term  <- positive_integer(),
            type  <- one_of([constant(:command), constant(:leader_elected), constant(:add_follower)]),
            data  <- one_of([atom(:alphanumeric), map_of(atom(:alphanumeric), string(:ascii))]) do
      %Entry{index: index, term: term, type: type, data: data}
    end
  end
end
