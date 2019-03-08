defmodule Raft.Server do
  @moduledoc """
  The Server module provides the raft fsm.
  """

  alias Raft.{
    Log,
    Log.Entry,
    Config,
    Configuration,
    RPC,
    RPC.AppendEntriesReq,
    RPC.AppendEntriesResp,
    RPC.RequestVoteReq,
    RPC.RequestVoteResp,
    Server.State,
  }

  require Logger

  @type state :: :leader
               | :follower
               | :candidate

  @type members :: %{required(atom()) => pid()}

  @typep status :: %{
    members: members(),
    current_state: state()
  }

  @initial_state %State{}

  def callback_mode, do: [:state_functions, :state_enter]

  @doc """
  This defines the child spec correctly
  """
  def child_spec(opts), do: %{
    id: __MODULE__,
    start: {__MODULE__, :start_link, [opts]},
    restart: :permanent,
    shutdown: 5000,
    type: :worker
  }

  @doc """
  Starts a new server.
  """
  @spec start_link({Raft.peer(), Config.t}) :: {:ok, pid} | {:error, term()}

  def start_link({name, config}) do
    case name do
      {me, _} ->
        :gen_statem.start_link({:local, me}, __MODULE__, {:follower, name, config}, [])

      ^name ->
        :gen_statem.start_link({:local, name}, __MODULE__, {:follower, name, config}, [])
    end
  end

  def set_configuration(peer, configuration) do
    :gen_statem.call(peer, {:set_configuration, configuration})
  end

  @doc """
  Creates a new cluster with a single server. Any existing logs or current term
  will be preserved however a new database id will be created for this cluster.
  If this is called on an existing server that server will be considered a new
  cluster and will no longer be able to communicate with its previous peers.
  """
  def initialize_cluster(peer) do
    :gen_statem.call(peer, :initialize_cluster)
  end

  @doc """
  Applies a new log to the application state machine. This is done in a highly
  consistent manor. This must be called on the leader or it will fail.
  """
  # @spec apply(server(), term()) :: :ok | {:error, :timeout} | {:error, :not_leader}

  def write(peer, cmd, timeout \\ 3_000) do
    :gen_statem.call(peer, {:write, cmd}, timeout)
  end

  @doc """
  Reads the current state from the state machine. This is done in a highly
  consistent manner. Reads must be executed on a leader and the leader must
  confirm that they have not been deposed before processing the read operation
  as described in the raft paper, section 8: Client Interaction.
  """
  def read(peer, cmd, timeout \\ 3_000) do
    :gen_statem.call(peer, {:read, cmd}, timeout)
  end

  @doc """
  Returns the name of the server that is believed to be the leader. This
  is not a consistent operation and during a network partition its possible that
  the server doesn't know who the latest elected leader is. This function should
  be used for testing and debugging purposes only.
  """
  @spec current_leader(atom()) :: atom()

  def current_leader(server) do
    status = :gen_statem.call(server, :status)
    status[:leader]
  end

  @doc """
  Gets the current status of the server.
  """
  @spec status(pid()) :: status()

  def status(sm) do
    :gen_statem.call(sm, :status)
  end

  @doc """
  Initializes the state of the server.
  If log files already exist for this server name then it reads from those
  files to get the current configuration, term, etc.
  """
  def init({:follower, name, config}) do
    Logger.info(fmt(%{me: name}, :follower, "Starting Raft state machine"))

    %{term: current_term} = Log.get_metadata(name)
    configuration = Log.get_configuration(name)
    state = %{ @initial_state |
      me: name,
      state_machine: config.state_machine,
      state_machine_state: config.state_machine.init(name),
      config: config,
      current_term: current_term,
      configuration: configuration,
      database_id: nil
    }

    Logger.info(fmt(state, :follower, "State has been restored"), [server: name])
    {:ok, :follower, reset_timeout(state)}
  end

  #
  # Leader callbacks
  #

  # Entering the leader state
  def leader(:enter, old_state, data) do
    Logger.info(fmt(data, :leader, "Becoming leader"))
    index = Log.last_index(data.me)
    next_index = initial_indexes(data, index+1)
    match_index = initial_indexes(data, 0)
    data = %{data | next_index: next_index, match_index: match_index}
    data = %{data | leader: data.me}

    case data.init_config do
      {id, from} ->
        Logger.debug("#{name(data)}: Becoming leader with initial config")
        entry = Entry.configuration(data.current_term, data.configuration)
        data = append(data, id, from, entry)
        send_append_entries(data)
        %{data | init_config: :complete}

      :undefined ->
        entry = Entry.noop(data.current_term)
        data = append(data, entry)
        %{data | init_config: :complete}

      :complete ->
        entry = Entry.noop(data.current_term)
        append(data, entry)
    end

    {:keep_state, data, [{:state_timeout, heartbeat_timeout(), :heartbeat}]}
  end

  # Write new entries to the log and replicate
  def leader({:call, from}, {:write, {id, cmd}}, data) do
    Logger.info(fmt(data, :leader, "Writing new command to log"))

    entry = Entry.command(data.current_term, cmd)
    {:ok, last_index} = Log.append(data.me, [entry])
    new_match_index = Map.put(data.match_index, data.me, last_index)
    data = %{data | match_index: new_match_index}
    send_append_entries(data)
    data = add_client_req(data, id, from, last_index)

    {:keep_state, data}
  end

  # Process read requests by first ensuring that we're still the leader.
  def leader({:call, from}, {:read, {id, cmd}}, data) do
    Logger.info(fmt(data, :leader, "Leader received read request"))
    data = add_read_req(data, id, from, cmd)
    send_append_entries(data)

    {:keep_state, data}
  end

  def leader(:state_timeout, :heartbeat, data) do
    Logger.debug(fmt(data, :leader, "Sending heartbeats"))

    send_append_entries(data)
    {:keep_state_and_data, [{:state_timeout, heartbeat_timeout(), :heartbeat}]}
  end

  # We're out of date so step down
  def leader(:cast, %AppendEntriesResp{success: false, term: term},
                    %{current_term: current_term}=data) when term > current_term do
    Logger.warn(fmt(data, :leader, "Out of date, stepping down as leader"))

    {:next_state, :follower, %{data | current_term: term}}
  end

  # Follower needs to be caught up so decrement the followers next index.
  # The next time a heartbeat times out we will send them all of the entries
  # and hopefully catch them up. If they aren't then we try again.
  def leader(:cast, %AppendEntriesResp{success: false, from: from}, data) do
    next_index = Map.update!(data.next_index, from, & &1-1)
    Logger.warn(
      fmt(data, :leader, "#{name(from)} is out of date. Decrementing index to #{next_index[from]}"))

    {:next_state, :leader, %{data | next_index: next_index}}
  end

  # Stale reply so ignore it
  def leader(:cast, %AppendEntriesResp{success: true, term: term},
                    %{current_term: current_term}=data) when current_term > term do
    Logger.debug(fmt(data, :leader, "Stale reply"))
    :keep_state_and_data
  end

  # Succeeded to replicate to follower
  def leader(:cast, %AppendEntriesResp{success: true, from: from, index: index}, data) do
    Logger.debug(fmt(data, :leader, "Successfully replicated index #{index} to #{name(from)}"))
    match_index = Map.put(data.match_index, from, index)
    next_index = Map.put(data.next_index, from, index+1)
    data = %{data | match_index: match_index, next_index: next_index}
    data = maybe_commit_logs(data)
    data = maybe_send_read_replies(data)

    {:keep_state, data}
  end

  def leader(msg, event, data) do
    handle_event(msg, event, :leader, data)
  end

  #
  # Follower callbacks
  #

  def follower(:enter, old_state, data) do
    Logger.debug("Becoming a follower from #{old_state}")

    {:keep_state, data, [{:timeout, election_timeout(data), :timeout}]}
  end

  # Timeout has happened so if we have a vote we should become a candidate
  # and start a new election. Otherwise we just wait for a new leader
  def follower(:timeout, :timeout, %{configuration: config}=data) do
    case Configuration.has_vote?(data.me, config) do
      true ->
        Logger.warn(fmt(data, :follower,
          "Becoming candidate of term: #{data.current_term+1}"
        ))
        {:next_state, :candidate, data}

      false ->
        Logger.debug(fmt(data, :follower, "Skipping until we have a vote"))
        data = %{data | leader: :none}
        {:next_state, :follower, data}
    end
  end

  # We can set the configuration if we're in follower state and we have no
  # configuration (which means the log is empty). This is so we can
  # bootstrap a new server.
  def follower({:call, from}, {:set_configuration, {id, peers}},
                              %{configuration: %{state: :none}}=state) do
    Logger.debug(fmt(state, :follower, "Setting initial configuration"))

    case Enum.member?(peers, state.me) do
      true ->
        config = Configuration.reconfig(state.configuration, peers)
        followers = Configuration.followers(config, state.me)
        new_state = %{state |
          followers: followers,
          configuration: config,
          init_config: {id, from}
        }
        {:next_state, :candidate, new_state}

      false ->
        rpy = {:reply, from, {:error, :must_be_in_consesus_group}}
        {:next_state, :follower, [rpy]}
    end
  end

  def follower({:call, from}, {:set_configuration, _change}, state) do
    Logger.warn(fmt(state, :follower,
      "Can't set config on a follower that already has a configuration"
    ))

    {:next_state, :follower, [{:reply, from, {:error, {:redirect, state.leader}}}]}
  end

  # Leader has a lower term then us
  def follower({:call, from}, %AppendEntriesReq{term: term},
               %{current_term: current_term}=state) when current_term > term do
    Logger.debug(fmt(state, :follower,
      "Rejected append entries from leader with a lower term"
    ))
    resp = %AppendEntriesResp{from: state.me, term: current_term, success: false}

    rpy = {:reply, from, resp}
    {:keep_state_and_data, [rpy, {:timeout, election_timeout(state), :timeout}]}
  end

  # Append entries looks good so lets try to save them.
  def follower({:call, from}, %AppendEntriesReq{}=req, state) do
    # state = reset_timeout(state)
    state = set_term(req.term, state)

    resp = %AppendEntriesResp{
      success: false,
      term: state.current_term,
      from: state.me
    }

    if consistent?(req, state) do
      Logger.debug(fn ->
        count = Enum.count(req.entries)
        me = state.me
        indexes = Enum.map(req.entries, & &1.index)
        "#{name(state)}: Log is consistent. Appending #{count} new entries at indexes: #{inspect indexes}"
      end)

      {:ok, index} = Log.append(state.me, req.entries)
      configuration = Log.get_configuration(state.me)
      state = commit_entries(req.leader_commit, state)
      state = %{state | leader: req.from, configuration: configuration}
      resp = %{resp | success: true, index: index}

      {:keep_state, state, [{:reply, from, resp}, {:timeout, election_timeout(state), :timeout}]}
    else
      Logger.warn("#{name(state)}: Our log is inconsistent with the leaders")
      last_index = Log.last_index(state.me)
      prev = req.prev_log_index
      if prev <= last_index do
        Logger.warn fn ->
          "#{name(state)}: Clearing logs from #{prev} to #{last_index}"
        end
        Log.delete_range(state.me, prev, last_index)
      end

      {:keep_state, state, [{:reply, from, resp}, {:timeout, election_timeout(state), :timeout}]}
    end
  end

  def follower({:call, from}, %RequestVoteReq{}=req, state) do
    handle_vote(from, req, state)
  end

  def follower({:call, from}, {:write, _}, state) do
    Logger.warn("#{name(state)}: Can't write on a server that isn't the leader")
    {:keep_state_and_data, [{:reply, from, {:error, {:redirect, state.leader}}}]}
  end

  def follower({:call, from}, {:read, _}, state) do
    Logger.warn("#{name(state)}: Can't read from a server that isn't the leader")
    {:keep_state_and_data, [{:reply, from, {:error, {:redirect, state.leader}}}]}
  end

  def follower(event, msg, state) do
    handle_event(event, msg, :follower, state)
  end

  #
  # Candidate callbacks
  #

  # If we're becoming a candidate then we should vote for ourselves and send
  # out vote requests to all other servers.
  def candidate(:enter, :follower, data) do
    data = State.increment_term(data)
    data = %{data | leader: :none}
    data = State.add_vote(data, %{vote_granted: true})
    :ok = vote_for_myself(data)

    data.configuration
    |> Configuration.followers(data.me)
    |> Enum.map(request_vote(data))
    |> RPC.broadcast

    {:keep_state, data, [{:state_timeout, election_timeout(data), :timeout}]}
  end

  # if we can't get a quorum on our initial election we let the client know
  # that there was an error and retry until the nodes come up
  def candidate(:state_timeout, :timeout, %{term: 1, init_config: {_id, from}}=state) do
    Logger.warn("#{name(state)}: Cluster is unreachable for initial configuration")
    :gen_statem.reply(from, {:error, :peers_not_responding})
    {:next_state, :candidate, state}
  end

  # If we get a timeout in an election then re-start the election
  def candidate(:state_timeout, :timeout, data) do
    Logger.warn("#{name(data)}: Timeout reached. Re-starting Election")

    {:next_state, :candidate, data}
  end

  # Reject any requests to set configuration while we're in the middle of an
  # election
  def candidate({:call, from}, {:set_configuration, _change}, _state) do
    {:keep_state_and_data, [{:reply, from, {:error, :election_in_progress}}]}
  end

  # A peer is trying to become leader. If it has a higher term then we
  # need to step down and become a follower
  def candidate({:call, from}, %RequestVoteReq{}=req, data) do
    cond do
      req.term > data.current_term ->
        Logger.warn fn ->
          "#{name(data)}: Received vote request with higher term: #{req.term}. Ours: #{data.current_term}. Stepping down"
        end
        data = step_down(data, req.term)
        handle_vote(from, req, data)

      true ->
        resp = vote_resp(req.from, data, false)
        {:keep_state_and_data, [{:reply, from, resp}]}
    end
  end

  def candidate(:cast, %RequestVoteResp{}=resp, state) do
    Logger.debug("#{name(state)}: Received vote")

    # TODO - Make sure that this can handle duplicate deliveries
    state = State.add_vote(state, resp)

    cond do
      resp.term > state.current_term ->
        Logger.warn("#{name(state)}: Newer term discovered, falling back to follower")
        {:next_state, :follower, %{state | current_term: resp.term}}

      State.majority?(state) ->
        Logger.info("#{name(state)}: Election won in term #{state.current_term}. Tally: #{state.votes}")

        {:next_state, :leader, state}

      true ->
        Logger.warn(
          "Vote granted from #{name(resp.from)} to #{name(state)} in term #{state.current_term}. " <>
          "Tally: #{state.votes}"
        )
        {:next_state, :candidate, state}
    end
  end

  # A server is sending us append entries which must mean they've been elected
  # leader. We should fallback to follower status
  def candidate({:call, _from}, %AppendEntriesReq{term: term},
                %{current_term: our_term}=state) when term >= our_term do
    Logger.debug("#{name(state)}: Received append entries. Stepping down")
    state = step_down(state, term)
    {:next_state, :follower, state, []}
  end

  # Ignore append entries that are below our current term
  def candidate({:call, _from}, %AppendEntriesReq{}, state) do
    Logger.debug("#{name(state)}: Ignoring stale append entries")
    {:keep_state_and_data, []}
  end

  def candidate({:call, from}, {:write, _}, _state) do
    Logger.warn("Can't write to a server that isn't the leader")
    {:keep_state_and_data, [{:reply, from, {:error, :election_in_progress}}]}
  end

  def candidate({:call, from}, {:read, _}, _state) do
    Logger.warn("Can't from a server that isn't the leader")
    {:keep_state_and_data, [{:reply, from, {:error, :election_in_progress}}]}
  end

  def candidate(msg, event, data) do
    handle_event(msg, event, :candidate, data)
  end

  #
  # Generic Callbacks
  #

  def handle_event({:call, from}, :status, current_state, state) do
    status = %{
      name: state.me,
      current_state: current_state,
      leader: state.leader,
      configuration: state.configuration,
      last_index: Log.last_index(state.me),
      last_term: Log.last_term(state.me),
    }

    {:keep_state_and_data, [{:reply, from, status}]}
  end

  def handle_event({:call, from}, :initialize_cluster, _, data) do
    database_id = UUID.uuid4()
    data = %{data | database_id: database_id}

    {:next_state, :follower, data, [{:reply, from, database_id}]}
  end

  def handle_event(event_type, event, state, _data) do
    Logger.debug(fn ->
      "Unhandled event, #{inspect event_type}, #{inspect event}, #{inspect state}"
    end)

    {:keep_state_and_data, []}
  end

  # TODO - We need to error any pending client requests due to an
  # initial misconfiguration.
  defp step_down(state, term) do
    state = %{state | current_term: term, leader: :none}
    Log.set_metadata(state.me, :none, term)
    state
  end

  defp handle_vote(from, req, state) do
    Logger.debug("Getting a vote request")
    state        = set_term(req.term, state)
    metadata     = Log.get_metadata(state.me)
    vote_granted = vote_granted?(req, metadata, state)
    resp         = vote_resp(req.from, state, vote_granted)

    Logger.info("#{name(state)}: Vote granted for #{name(req.from)}? #{vote_granted}")

    if vote_granted do
      :ok = persist_vote(state.me, req.term, req.from)
    end

    {:next_state, :follower, state, [{:reply, from, resp}]}
  end

  defp vote_granted?(req, meta, state) do
    cond do
      req_is_behind?(req, state) ->
        Logger.debug("#{name(state)}: Request is behind")
        false

      voted_for_someone_else?(req, meta) ->
        Logger.debug("#{name(state)}: Already voted in this term")
        false

      !candidate_up_to_date?(req, state) ->
        Logger.debug("#{name(state)}: Candidate is not up to date. Rejecting vote")
        false

      true ->
        true
    end
  end

  defp req_is_behind?(%{term: rt}, %{current_term: ct}), do: rt < ct

  defp voted_for_someone_else?(%{term: term, from: candidate},
                               %{term: term, voted_for: candidate}) do
    false
  end
  defp voted_for_someone_else?(%{term: term},
                               %{term: term, voted_for: :none}) do
    false
  end
  defp voted_for_someone_else?(%{term: term, from: candidate},
                               %{term: term, voted_for: someone}) do
    candidate != someone
  end

  defp candidate_up_to_date?(%{last_log_index: c_term, last_log_term: c_index},
                             %{me: me}) do
    our_term   = Log.last_term(me)
    last_index = Log.last_index(me)
    up_to_date?(c_term, c_index, our_term, last_index)
  end

  def up_to_date?(cand_term, _, our_term, _) when cand_term > our_term do
    true
  end
  def up_to_date?(cand_term, _, our_term, _) when cand_term < our_term do
    false
  end
  def up_to_date?(term, cand_index, term, our_index) when cand_index > our_index do
    true
  end
  def up_to_date?(term, cand_index, term, our_index) when cand_index < our_index do
    false
  end
  def up_to_date?(term, index, term, index) do
    true
  end

  defp election_timeout(%{config: config}) do
    Config.election_timeout(config)
  end

  defp heartbeat_timeout, do: 25

  defp reset_timeout(state) do
    reset_timeout(election_timeout(state), state)
  end

  defp reset_timeout(timeout, %{timer: timer}=state) do
    if timer do
      _ = Process.cancel_timer(timer)
    end

    timer = Process.send_after(self(), :timeout, timeout)
    %{state | timer: timer}
  end

  defp vote_for_myself(state) do
    persist_vote(state.me, state.current_term, state.me)
  end

  defp persist_vote(name, term, candidate) do
    :ok = Log.set_metadata(name, candidate, term)
  end

  defp previous(_state, 1), do: {0, 0}
  defp previous(state, index) do
    prev_index = index-1
    {:ok, log} = Log.get_entry(state.me, prev_index)
    {prev_index, log.term}
  end

  defp get_entries(%{me: me}, index) do
    # TODO - Get a slice of logs here.
    case Log.get_entry(me, index) do
      {:ok, entry} ->
        [entry]

      {:error, :not_found} ->
        []
    end
  end

  defp send_entry(%{next_index: indexes, commit_index: commit_index}=state) do
    fn server ->
      index = indexes[server]
      {prev_index, prev_term} = previous(state, index)
      logs = get_entries(state, index)

      %RPC.AppendEntriesReq{
        to: server,
        from: state.me,
        leader_id: state.me,
        prev_log_index: prev_index,
        prev_log_term: prev_term,
        leader_commit: commit_index,
        term: state.current_term,
        entries: logs,
      }
    end
  end

  defp request_vote(state) do
    fn server ->
      last_index = Log.last_index(state.me)
      last_term  = Log.last_term(state.me)

      %RPC.RequestVoteReq{
        to: server,
        from: state.me,
        term: state.current_term,
        candidate_id: state.me,
        last_log_index: last_index,
        last_log_term: last_term,
      }
    end
  end

  defp vote_resp(server, state, vote_granted) do
    %RequestVoteResp{
      to: server,
      from: state.me,
      term: state.current_term,
      vote_granted: vote_granted,
    }
  end

  defp append(state, entry) do
    {:ok, index} = Log.append(state.me, [entry])
    match_index = Map.put(state.match_index, state.me, index)
    send_append_entries(state)
    %{state | match_index: match_index}
  end

  defp append(state, id, from, entry) do
    {:ok, index} = Log.append(state.me, [entry])
    match_index = Map.put(state.match_index, state.me, index)
    req = %{id: id, from: from, index: index, term: state.current_term}
    %{state | client_reqs: [req | state.client_reqs], match_index: match_index}
  end

  defp maybe_send_read_replies(%{configuration: conf, match_index: mi}=state) do
    Logger.debug("#{name(state)}: Sending any eligible read requests")

    commit_index = Configuration.quorum_max(conf, mi)
    {elegible, remaining} = elegible_requests(state, commit_index)
    state = read_and_send(state, elegible)
    %{state | read_reqs: remaining}
  end

  defp add_read_req(state, id, from, cmd) do
    req = %{
      id: id,
      index: state.commit_index,
      from: from,
      cmd: cmd,
      term: state.current_term,
    }

    %{state | read_reqs: [req | state.read_reqs]}
  end

  defp read_and_send(%{state_machine: sm, state_machine_state: sms}=state, reqs) do
    new_state = Enum.reduce reqs, sms, fn req, s ->
      {result, new_state} = sm.handle_read(req.cmd, s)
      respond_to_client(req, result)
      new_state
    end

    %{state | state_machine_state: new_state}
  end

  defp elegible_requests(%{read_reqs: reqs}, index) do
    elegible  = Enum.take_while(reqs, fn %{index: i} -> index >= i end)
    remaining = Enum.drop_while(reqs, fn %{index: i} -> index >= i end)
    {elegible, remaining}
  end

  # TODO - pull this apart so it just returns the new commit index and we can
  # take actions in the leader callback
  defp maybe_commit_logs(state) do
    commit_index = Configuration.quorum_max(state.configuration, state.match_index)
    cond do
      commit_index > state.commit_index and safe_to_commit?(commit_index, state) ->
        Logger.debug("#{name(state)}: Committing to index #{commit_index}")
        commit_entries(commit_index, state)

      commit_index == state.commit_index ->
        Logger.debug("#{name(state)}: No new entries to commit.")
        state

      true ->
        Logger.debug("#{name(state)}: Not committing since there isn't a quorum yet.")
        state
    end
  end

  defp safe_to_commit?(index, %{current_term: term, me: me}) do
    with {:ok, log} <- Log.get_entry(me, index) do
      log.term == term
    else
      _ ->
        false
    end
  end

  defp initial_indexes(state, index) do
    state.configuration
    |> Configuration.servers
    |> Enum.map(fn f -> {f, index} end)
    |> Enum.into(%{})
  end

  defp set_term(term, %{current_term: current_term, me: me}=state) do
    cond do
      term > current_term ->
        Log.set_metadata(me, :none, term)
        %{state | current_term: term}

      term < current_term ->
        state

      true ->
        state
    end
  end

  defp seq(a, b), do: :lists.seq(a, b)

  defp commit_entries(leader_commit, %{commit_index: commit_index}=state) when commit_index >= leader_commit do
    state
  end

  # Starting at the last known index and working towards the new last index
  # apply each log to the state machine
  defp commit_entries(leader_commit, %{commit_index: starting_index}=state) do
    # Returns the last possible index. Its either the index they want us to
    # commit to or the largest index that we have in our log
    last_index = min(leader_commit, Log.last_index(state.me))

    Logger.debug("#{name(state)}: Committing from #{starting_index+1} to #{last_index}")

    seq(starting_index+1, last_index)
    |> Enum.reduce(state, &commit_entry/2)
  end

  defp commit_entry(index, state) do
    state = %{state | commit_index: index}
    Logger.debug("#{name(state)}: Getting entry: #{index}")
    case Log.get_entry(state.me, index) do
      {:ok, %{type: :noop}} ->
        state

      {:ok, %{type: :command, data: cmd}=log} ->
        {result, new_sms} = apply_log_to_state_machine(state, cmd)
        reqs = respond_to_client_requests(state, log, result)
        %{state | state_machine_state: new_sms, client_reqs: reqs}

      {:ok, %{type: :config, data: %{state: :stable}}=log} ->
        rpy = {:ok, state.configuration}
        reqs = respond_to_client_requests(state, log, rpy)
        %{state | client_reqs: reqs}
    end
  end

  defp respond_to_client_requests(%{client_reqs: reqs, leader: me, me: me},
                                  log, rpy) do
    reqs
    |> Enum.filter(fn req -> req.index == log.index end)
    |> Enum.each(fn req -> respond_to_client(req, rpy) end)

    Enum.reject(reqs, fn req -> req.index == log.index end)
  end
  defp respond_to_client_requests(%{client_reqs: reqs}, _, _) do
    reqs
  end

  defp respond_to_client(%{from: from}, rpy) do
    :gen_statem.reply(from, rpy)
  end

  defp consistent?(%{prev_log_index: 0, prev_log_term: 0}, _), do: true
  defp consistent?(%{prev_log_index: index, prev_log_term: term}, state) do
    case Log.get_entry(state.me, index) do
      {:ok, %{term: entry_term}} ->
        term == entry_term

      {:error, :not_found} ->
        false
    end
  end

  defp send_append_entries(state) do
    state.configuration
    |> Configuration.followers(state.me)
    |> Enum.map(send_entry(state))
    |> RPC.broadcast
  end

  defp apply_log_to_state_machine(%{state_machine: sm, state_machine_state: sms}, cmd) do
    sm.handle_write(cmd, sms)
  end

  defp add_client_req(state, id, from, index) do
    req = %{id: id, from: from, index: index, term: state.current_term}
    %{state | client_reqs: [req | state.client_reqs]}
  end

  defp fmt(state, fsm_state, msg) do
    fn ->
      "#{name(state)} - #{fsm_state}: #{msg}"
    end
  end

  defp name(%{me: {me, _}}), do: me
  defp name(%{me: me}), do: me
  defp name({me, _}), do: me
  defp name(me) when is_atom(me), do: me
end
