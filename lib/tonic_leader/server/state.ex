defmodule TonicLeader.Server.State do
  alias TonicLeader.{Log, Config, Configuration}
  alias __MODULE__

  defstruct [
    # configurations: %{
    #   latest: nil,
    #   latest_index: 0,
    #   servers: [],
    # },
    config: nil,
    configuration: %Configuration{},
    current_leader: :none,
    current_term: 0,
    election_timeout: 0,
    election_timer: nil,
    last_index: 0,
    log: %Log{},
    log_store: nil,
    next_index: nil, #only used for the leader, index of the next log entry to send to a server
    match_index: nil, # for each server, index of highest log entry known to be replicated on server
  ]

  def new(config, log_store, last_index, current_term, configuration) do
    %__MODULE__{}
    |> Map.put(:config, config)
    |> Map.put(:log_store, log_store)
    |> Map.put(:last_index, last_index)
    |> Map.put(:current_term, current_term)
    |> Map.put(:configuration, configuration)
  end

  def next_election_timeout(state, cb) do
    timeout = Config.election_timeout(state.config)
    %State{state | election_timer: cb.(timeout)}
  end

  def last_index(state) do
    state.latest_index
  end
end
