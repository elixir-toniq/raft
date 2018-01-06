defmodule TonicLeader do
  alias TonicLeader.{Server, Log, LogStore, Config, StableStore}
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
    Logger.debug("Bootstrapping #{config.name}")

    {:ok, log_store} = LogStore.open(Config.db_path(config))

    # Check to see if this server already has storage; fail if it does
    if LogStore.has_data?(log_store) do
      raise "Data already exists for this server. Its not safe to bootstrap it"
    end

    # Store the configuration
    Logger.debug("Storing configuration for #{config.name}")
    log = Log.configuration(1, 1, configuration)
    :ok = LogStore.store_logs(log_store, [log])

    # Store the current term as 1
    :ok = LogStore.set(log_store, "CurrentTerm", 1)

    # Close the db
    LogStore.close(log_store)

    # Start server
    Server.Supervisor.start_server(config)
  end

  def test_mode() do
    alias TonicLeader.{Configuration, Config}

    :tonic_leader
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    configuration = %Configuration{
      servers: [
        Configuration.voter(:s1, node()),
        Configuration.voter(:s2, node()),
        Configuration.voter(:s3, node()),
      ],
      index: 1,
    }
    {:ok, s1} = TonicLeader.bootstrap(%Config{name: :s1}, configuration)
    {:ok, s2} = TonicLeader.bootstrap(%Config{name: :s2}, configuration)
    {:ok, s3} = TonicLeader.bootstrap(%Config{name: :s3}, configuration)

    {s1, s2, s3}
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

