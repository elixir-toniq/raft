defmodule TonicLeader.RPC.AppendEntries do
  @enforce_keys [:term, :leader_id, :prev_log_index, :prev_log_term, :entries, :leader_commit]
  defstruct [
    :term,
    :leader_id,
    :prev_log_index,
    :prev_log_term,
    :entries,
    :leader_commit
  ]

  defmodule Response do
    defstruct [
      :term,
      :success,
    ]
  end
end
