defmodule Raft.RPC.RequestVote do
  defstruct [
    :term,
    :candidate_id,
    :last_log_index,
    :last_log_term,
  ]

  defmodule Result do
    defstruct [
      :term,
      :vote_granted,
    ]
  end
end
