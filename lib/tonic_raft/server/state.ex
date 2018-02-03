defmodule TonicRaft.Server.State do
  alias TonicRaft.{Configuration}

  defstruct [
    me: nil,
    config: nil,
    state_machine: nil,
    state_machine_state: nil,
    current_term: 0,
    client_reqs: [],
    read_reqs: [],
    leader: :none,
    followers: [],
    init_config: :undefined,
    timer: nil,
    commit_index: 0,
    configuration: nil,
    next_index: nil, #only used for the leader, index of the next log entry to send to a server
    match_index: nil, # for each server, index of highest log entry known to be replicated on server
    votes: 0, # Only used when in candidate mode and tallying votes
  ]

  def new(config, log_store, last_index, current_term, configuration) do
    %__MODULE__{}
    |> Map.put(:config, config)
    |> Map.put(:log_store, log_store)
    |> Map.put(:last_index, last_index)
    |> Map.put(:current_term, current_term)
    |> Map.put(:configuration, configuration)
  end

  def increment_term(state) do
    Map.update!(state, :current_term, & &1+1)
  end

  def last_index(state) do
    state.latest_index
  end

  def add_vote(state, %{vote_granted: true}), do: %{state | votes: state.votes+1}
  def add_vote(state, _), do: state

  def majority?(state) do
    state.votes >= Configuration.quorum(state.configuration)
  end
end
