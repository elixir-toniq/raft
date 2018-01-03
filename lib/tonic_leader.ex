defmodule TonicLeader do
  # @opaque group_name :: String.t
  # @doc """
  # Returns all of the members of a group based on a group name
  # """

  # @spec members(group_name()) :: %{optional(atom()) => pid()}
  # def members(group_name) do
  # end

  alias TonicLeader.{Log, LogStore, Config}
  require Logger

  @doc """
  Bootstraps a server. You must be careful when using this command.
  Bootstrapping should only be done to initialize a cluster. If this command is
  run after a configuration has already been stored for a cluster then
  its possible to overwrite or otherwise corrupt that configuration.

  Care must be taken to use the identical configuration on each node in the
  cluster.

  Another option for starting a new cluster would be to bootstrap a single node
  as a leader and then use `add_voter/2` to add servers to the cluster.
  """

  def bootstrap(config, configuration) do
    {:ok, log_store} = LogStore.open(Config.db_path(config))

    # Check to see if this server already has storage; fail if it does
    if has_data?(log_store) do
      raise "Log data already exists for this server. Its not safe to bootstrap it"
    end

    # Store the configuration
    Logger.debug("Storing configuration for #{config.name}")
    log = Log.configuration(1, 1, configuration)
    :ok = LogStore.store_logs(log_store, [log])

    # Store the current term as 1
    LogStore.close(log_store)

    # Start server
    Server.Supervisor.start_server(config)
  end

  def has_data?(log_store) do
    LogStore.last_index(log_store) > 0
  end

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

