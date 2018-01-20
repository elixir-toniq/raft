defmodule TonicRaft.Server.State do
  alias TonicRaft.{Log, Config, Configuration}
  alias __MODULE__

  defstruct [
    # configurations: %{
    #   latest: nil,
    #   latest_index: 0,
    #   servers: [],
    # },
    me: nil,
    config: nil,
    configuration: %Configuration{},
    current_leader: :none,
    current_term: 0,
    client_reqs: [],
    election_timeout: 0,
    election_timer: nil,
    leader: :none,
    followers: [],
    init_config: :complete,
    timer: nil,
    last_index: 0,
    commit_index: 0,
    log: %Log{},
    log_store: nil,
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

  def reset_timeout(state, cb) do
    if state.election_timer do
      Process.cancel_timer(state.election_timer)
    end

    timeout = Config.election_timeout(state.config)
    %State{state | election_timeout: timeout, election_timer: cb.(timeout)}
  end

  def next_election_timeout(state, cb) do
    if state.election_timer do
      Process.cancel_timer(state.election_timer)
    end

    timeout = Config.election_timeout(state.config)
    %State{state | election_timeout: timeout, election_timer: cb.(timeout)}
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
