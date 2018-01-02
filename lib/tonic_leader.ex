defmodule TonicLeader do
  # @opaque group_name :: String.t
  # @doc """
  # Returns all of the members of a group based on a group name
  # """

  # @spec members(group_name()) :: %{optional(atom()) => pid()}
  # def members(group_name) do
  # end

  @doc """
  Used to apply a new change to the application fsm. Leader ensures that this
  is done in consistent manner.
  """
  @spec apply(any()) :: :ok | {:error, :timeout} | {:error, :not_leader}
  def apply(cmd) do

  end

  @doc """
  Adds a server to the cluster. The new server will be added in a staging mode.
  Once the new server is ready the leader will promote the new server to a
  follower.
  """
  @spec add_voter(atom(), pid()) :: :ok

  def add_voter(name, pid) do
    # Send this thing somewhere
    #
  end
end

