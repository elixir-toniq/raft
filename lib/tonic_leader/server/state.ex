defmodule TonicLeader.Server.State do
  alias TonicLeader.Log
  alias __MODULE__

  defstruct [
    configurations: %{
      latest: nil,
      latest_index: 0,
      servers: [],
    },
    current_leader: :none,
    current_term: 0,
    election_timeout: 0,
    last_index: 0,
    log: %Log{},
    log_store: nil,
    next_index: nil, #only used for the leader, index of the next log entry to send to a server
    match_index: nil, # for each server, index of highest log entry known to be replicated on server
  ]

  def latest_index(state) do
    state.latest_index
  end
end
