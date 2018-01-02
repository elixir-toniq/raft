defmodule TonicLeader.RPC do
  alias TonicLeader.Log

  @type server :: pid()
  @type msg :: AppendEntriesReq
             | AppendEntriesResp
             | RequestVoteReq
             | RequestVoteResp

  defmodule AppendEntriesReq do
    @enforce_keys [:leader_id, :entries, :prev_log_index, :prev_log_term, :leader_commit]
    defstruct [
      :leader_id, # We need this so we can respond to the correct pid and so 
                  # followers can redirect clients
      :entries, # Log entries to store. This is empty for heartbeats
      :prev_log_index, # index of log entry immediately preceding new ones
      :prev_log_term, # term of previous log index entry
      :leader_commit, # The leaders commit index
    ]
  end

  defmodule AppendEntriesResp do
    defstruct [
      :from, # We need this so we can track who sent us the message
      :term, # The current term for the leader to update itself
      :success, # true if follower contained entry matching prev_log_index and
                # prev_log_term
    ]
  end

  defmodule RequestVoteReq do
    defstruct [
      :term, # candidates term
      :candidate_id, # candidate requesting vote
      :last_log_index, # index of candidates last log entry
      :last_log_term, # term of candidates last log entry
    ]
  end

  defmodule RequestVoteResp do
    defstruct [
      :from, # pid that the message came from
      :term, # current term for the candidate to update itself
      :voteGranted, # true means candidate received vote
    ]
  end

  def replicate(state, log) do
    state.configurations.latest.servers
    |> Enum.reject(self())
    |> Enum.map(append_entries(log))
    |> Enum.each(&send_msg/1)
  end

  @doc """
  Sends a message to a server
  """
  @spec send_msg({server, msg()}) :: :ok

  def send_msg({server, msg}) do
    GenStateMachine.cast(server, msg)
  end

  defp append_entries(log) do
    fn member ->
      entries = Log.from_index(log, member.next_index)
      req = %AppendEntriesReq{
        leader_id: self(),
        entries: entries,
        prev_log_index: nil,
        prev_log_term: nil,
        leader_commit: nil,
      }
      {member, req}
    end
  end
end
