defmodule TonicRaft do
  alias TonicRaft.{Server, Config, Configuration}
  require Logger

  @type peer :: atom() | {atom(), atom()}

  @doc """
  Starts a new peer with a given Config.t.
  """
  @spec start_node(peer(), Config.t) :: {:ok, term()} | {:error, term()}

  def start_node(name, opts) do
    TonicRaft.Server.Supervisor.start_peer(name, opts)
  end

  @doc """
  Used to apply a new change to the application fsm. Leader ensures that this
  is done in consistent manner. This operation blocks until the log has been
  replicated to a majority of servers.
  """
  @spec apply(term(), list()) :: {:ok, term()} | {:error, :timeout} | {:error, :not_leader}

  def apply(_cmd, _opts) do
    {:ok, :not_implemented}
  end

  @doc """
  Returns the leader according to the given peer.
  """
  @spec leader(peer()) :: peer() | :none

  def leader(name) do
    Server.current_leader(name)
  end

  @doc """
  Sets peers configuration. The new configuration will be merged with any
  existing configuration.
  """
  @spec set_configuration(peer(), [peer()]) :: {:ok, Configuration.t}
                                                    | {:error, term()}

  def set_configuration(peer, configuration) do
    id = UUID.uuid4()
    Server.set_configuration(peer, {id, configuration})
  end

  @doc """
  Creates a test cluster for running on a single. Should only be used for
  development and testing.
  """
  @spec test_cluster() :: {peer(), peer(), peer()}
  def test_cluster() do
    path =
      File.cwd!
      |> Path.join("test_data")

    File.rm_rf!(path)
    File.mkdir(path)

    {:ok, s1} = TonicRaft.start_node(:s1, %Config{data_dir: path})
    {:ok, s2} = TonicRaft.start_node(:s2, %Config{data_dir: path})
    {:ok, s3} = TonicRaft.start_node(:s3, %Config{data_dir: path})

    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = TonicRaft.set_configuration(:s1, nodes)

    {s1, s2, s3}
  end
end

