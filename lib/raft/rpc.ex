defmodule Raft.RPC do
  @moduledoc """
  Defines multiple rpc commands and functions for broadcasting messages to other
  peers.
  """

  alias Raft.Configuration.Server

  require Logger

  defmodule AppendEntriesReq do
    @enforce_keys [:leader_id, :entries, :prev_log_index, :prev_log_term, :leader_commit]
    defstruct [
      :to, #Who we're sening this to
      :term, # Leaders current term
      :from, # Who sent this
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
      :to,
      :from, # We need this so we can track who sent us the message
      :term, # The current term for the leader to update itself
      :index, # The index we're at. Used to prevent re-commits with duplicate
              # Rpcs.
      :success, # true if follower contained entry matching prev_log_index and
                # prev_log_term
    ]
  end

  defmodule RequestVoteReq do
    defstruct [
      :to, # Who we're going to send this to. A %Server{}
      :term, # candidates term
      :from, # Who sent this message
      :candidate_id, # candidate requesting vote
      :last_log_index, # index of candidates last log entry
      :last_log_term, # term of candidates last log entry
    ]
  end

  defmodule RequestVoteResp do
    defstruct [
      :to, # Who we're sending this to
      :from, # pid that the message came from
      :term, # current term for the candidate to update itself
      :vote_granted, # true means candidate received vote
    ]
  end

  @type server :: pid()
  @type msg :: %AppendEntriesReq{}
             | %AppendEntriesResp{}
             | %RequestVoteReq{}
             | %RequestVoteResp{}

  def broadcast(rpcs) do
    Enum.map(rpcs, &send_msg/1)
  end

  @doc """
  Sends a message to a server
  """
  @spec send_msg(msg()) :: pid()

  def send_msg(%{from: from, to: to}=rpc) do
    spawn fn ->
      to
      |> Server.to_server
      |> GenStateMachine.call(rpc)
      |> case do
        %AppendEntriesResp{}=resp ->
          GenStateMachine.cast(from, resp)

        %RequestVoteResp{}=resp ->
          GenStateMachine.cast(from, resp)

        error ->
          Logger.error fn ->
            "Error: #{inspect error} sending #{inspect rpc} to #{to} from #{from}"
          end
      end
    end
  end
end
