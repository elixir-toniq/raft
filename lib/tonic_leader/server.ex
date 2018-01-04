defmodule TonicLeader.Server do
  use GenStateMachine, callback_mode: :state_functions

  alias TonicLeader.{RPC, Log, LogStore, Config, Configuration}
  alias TonicLeader.Server.State

  require Logger

  @type state :: :leader
               | :follower
               | :candidate

  @type members :: %{required(atom()) => pid()}

  @typep status :: %{
    members: members(),
    current_state: state()
  }

  @default_state %State{}

  def child_spec(opts), do: %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [opts]},
    restart: :permanent,
    shutdown: 5000,
    type: :worker
  }

  def start_link(%Config{}=config) do
    GenStateMachine.start_link(__MODULE__, {:follower, config})
  end
  def start_link(opts) do
    GenStateMachine.start_link(__MODULE__, {:follower, Config.new(opts)})
  end

  def get(sm, key) do
    GenStateMachine.call(sm, {:get, key})
  end

  def put(sm, key, value) do
    GenStateMachine.call(sm, {:put, key, value})
  end

  @doc """
  Returns the name of the server that is believed to be the leader. This
  is not a consistent operation and during a network partition its possible that
  the server doesn't know who the latest elected leader is. This function should
  be used for testing and debugging purposes only.
  """
  def leader(server) do
    status = GenStateMachine.call(server, :status)
    status[:current_leader]
  end

  @doc """
  Adds a new member to the cluster. The member is added as a follower.
  If this is a new server then the new member will be passed a snapshot
  in order to build the log locally. The new member will be unavailable for
  voting in a term until its persisted all of the log entries.
  """
  def add_voter(server, name, address) do
    change = %{
      command: :add_voter,
      name: name,
      address: address,
    }

    GenStateMachine.call(server, {:config_change, change})
  end

  @spec status(pid()) :: status()
  def status(sm) do
    GenStateMachine.call(sm, :status)
  end

  @doc """
  TODO: Implement this workflow.
  * Pull logs out of storage
  * Pull current term out of storage
  * Set a new election timeout
  * Find the most recent config change (start from most recent snapshot if we have one)
  * Restore state:
  * - set last index
  * - set last_log
  * - set current term
  * - set the configuration
  """
  def init({:follower, config}) do
    {:ok, log_store} = LogStore.open(Config.db_path(config))

    timeout   = Config.election_timeout(config)
    # state =
    #   @default_state
    #   |> Map.put(:log_store, log_store)
    #   |> Map.put(:election_timeout, 30_000)
    #   |> restore_state

    # Logger.info("State has been restored")

    # {:ok, :leader, state}

    {:ok, :follower,
      %{@default_state | log_store: log_store, election_timeout: timeout}}
  end

  def restore_state(%{log_store: log_store}=state) do
    Logger.info("Restoring old state")

    index = LogStore.last_index(log_store)
    last_log = LogStore.get(log_store, index)
    current_term = :rocksdb.get(log_store, "CurrentTerm", [])

    Logger.info("Getting all logs")

    state =
      1..index
      |> Enum.map(& LogStore.get(log_store, &1))
      |> Enum.map(fn {:ok, value} -> value end)
      |> Enum.filter(& &1["type"] == "config_change")
      |> Enum.reduce(state, &update_configuration/2)

    Logger.info("Got config change logs")

    state
    |> Map.put(:last_index, index)
    |> Map.put(:current_term, 1)
  end

  def update_configuration(config, state) do
    new_configurations =
      state.configurations
      |> put_in([:latest], config["data"])
      |> put_in([:latest_index], config["index"])

    %{state | configurations: new_configurations}
  end

  def has_data?(log_store) do
    LogStore.last_index(log_store) > 0
  end

  #
  # Leader callbacks
  #

  # Look up AddPeer in hashicorp/raft
  def leader({:call, _from}, {:config_change, config_change}, state) do
    case Configuration.next(state.configurations.latest, config_change) do
      {:ok, config} ->
        Logger.info("Updating configuration")
        index = State.last_index(state)
        term = state.term
        data = Configuration.encode(config)
        log = Log.configuration(index, term, data)

        case LogStore.store_logs(state.log_store, [log]) do
          :ok ->
            state = put_in(state.configurations, [:latest], config)
            state = put_in(state.configurations, [:latest_index], log.index)
            commitment = set_configuration(config)
            state
            |> RPC.replicate(log)

          {:error, e} ->
            Logger.error("Failed to store logs")
            :transition_to_follower
        end

      {:error, e} ->
        {:error, e}
    end
  end

  @doc """
  Sets the "commitment" for the server. i.e. how many servers need to vote
  in order to gain a majority. Resets the match_indexes for each server.
  """
  def set_configuration(config) do
  end

  def leader({:call, _from}, {:add_voter, voter}, state) do
    # * Creates new log entry for member addition
    # * Starts updating members
    # * If a membership change is already occuring then we can't add a new
    #   member until the change has been comitted so we return an error
    # * Persist log entries
    # * Grab a snapshot to send to the new follower
    # * broadcast changes to all other members
    # Log.add_member(data.logs)
    # {log, entry} = Log.add_member(state.log, state.term, member)
    # case LogStore.store_logs(state.log_store, [entry]) do
    #   {:ok, log} ->
    #     state
    #     |> State.add_member(member)
    #     |> RPC.broadcast_append_entries(log)
    #   {:error, e} ->
    #     throw e
    # end
  end

  def leader(msg, event, data) do
    handle_event(msg, event, :leader, data)
  end

  #
  # Follower callbacks
  #

  def follower({:call, from}, {:config_change, _change}, _state) do
    {:keep_state_and_data, [{:reply, from, {:error, :not_leader}}]}
  end

  def follower(msg, event, data) do
    handle_event(msg, event, :follower, data)
  end

  #
  # Candidate callbacks
  #

  def candidate({:call, from}, {:config_change, _change}, _state) do
    {:keep_state_and_data, [{:reply, from, {:error, :not_leader}}]}
  end

  def candidate(msg, event, data) do
    handle_event(msg, event, :candidate, data)
  end

  # def handle_event({:call, from}, :current_state, state, data) do
  #   {:next_state, state, data, [{:reply, from, state}]}
  # end

  # def handle_event({:call, from}, {:get, key}, state, data) do
  #   {:ok, value} = Log.get(key)
  #   {:keep_state_and_data, [{:reply, from, value}]}
  # end

  # def handle_event({:call, from}, {:put, key, value}, state, data) do
  #   {:ok, value} = Log.put(key, value)
  #   {:keep_state_and_data, [{:reply, from, value}]}
  # end

  def handle_event({:call, from}, :status, current_state, state) do
    status = %{
      current_state: current_state,
      current_leader: state.current_leader,
      configuration: state.configurations.latest,
    }
    {:keep_state_and_data, [{:reply, from, status}]}
  end

  def handle_event(:cast, :election_timeout, :follower, data) do
    new_data = data
    {:next_state, :candidate, new_data}
  end

  def handle_event(event_type, event, state, data) do
    IO.inspect([event_type, event, state, data])
  end
end

