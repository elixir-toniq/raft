defmodule TonicLeader.Server.State do
  alias TonicLeader.Log
  alias __MODULE__

  defstruct [
    configurations: %{
      latest: nil,
      latest_index: 0,
      servers: [],
    },
    current_term: 0,
    election_timeout: 0,
    members: [],
    last_index: 0,
    log: %Log{},
    log_store: nil,
    next_index: nil, #only used for the leader, index of the next log entry to send to a server
    match_index: nil, # for each server, index of highest log entry known to be replicated on server
  ]

  def add_member(state, member) do
    %State{state | members: [member | state.members]}
  end

  def latest_index(state) do
    state.latest_index
  end
end
