defmodule Raft do
  alias Raft.{
    Log,
    Server,
    Config,
    Configuration
  }
  require Logger

  @type peer :: atom() | {atom(), atom()}

  @doc """
  Starts a new peer with a given Config.t.
  """
  @spec start_node(peer(), Config.t) :: {:ok, pid()} | {:error, term()}

  def start_node(name, config \\ %Config{}) do
    Raft.Server.Supervisor.start_peer(name, config)
  end

  @doc """
  Gracefully stops the node.
  """
  def stop_node(name) do
    Raft.Server.Supervisor.stop_peer(name)
  end

  @doc """
  Used to apply a new change to the application fsm. This is done in consistent
  manner. This operation blocks until the log has been replicated to a
  majority of servers.
  """
  @spec write(peer(), term(), any()) :: {:ok, term()} | {:error, :timeout} | {:error, :not_leader}

  def write(leader, cmd, timeout \\ 3_000) do
    Raft.Server.write(leader, {UUID.uuid4(), cmd}, timeout)
  end

  @doc """
  Reads state that has been applied to the state machine.
  """
  @spec read(peer(), term(), any()) :: {:ok, term()} | {:error, :timeout} | {:error, :not_leader}

  def read(leader, cmd, timeout \\ 3_000) do
    Raft.Server.read(leader, {UUID.uuid4(), cmd}, timeout)
  end

  @doc """
  Returns the leader according to the given peer.
  """
  @spec leader(peer()) :: peer() | :none

  def leader(name) do
    Server.current_leader(name)
  end

  @doc """
  Returns the current status for a peer. This is used for debugging and
  testing purposes only.
  """
  @spec status(peer()) :: {:ok, %{}} | {:error, :no_node}

  def status(name) do
    {:ok, Raft.Server.status(name)}
  catch
    :exit, {:noproc, _} ->
      {:error, :no_node}
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
  Gets an entry from the log. This should only be used for testing purposes.
  """
  @spec get_entry(peer(), non_neg_integer()) :: {:ok, Log.Entry.t} | {:error, term()}
  def get_entry(to, index) do
    Log.get_entry(to, index)
  catch
    :exit, {:noproc, _} ->
      {:error, :no_node}
  end

  def test_node(name) do
    Raft.start_node({name, node()}, %Raft.Config{state_machine: Raft.StateMachine.Stack})
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

    {:ok, _s1} = Raft.start_node(:s1, %Config{data_dir: path})
    {:ok, _s2} = Raft.start_node(:s2, %Config{data_dir: path})
    {:ok, _s3} = Raft.start_node(:s3, %Config{data_dir: path})

    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = Raft.set_configuration(:s1, nodes)

    {:s1, :s2, :s3}
  end
end

