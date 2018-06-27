defmodule Raft do
  @moduledoc """
  Raft provides users with an api for building consistent (as defined by CAP), distributed
  state machines. It does this using the raft leader election and concensus
  protocol as described in the [original paper](https://raft.github.io/raft.pdf).

  ## Example

  Lets create a distributed key value store. The first thing that we'll need is
  a state machine:

  ```
  defmodule KVStore do
    use Raft.StateMachine

    @initial_state %{}

    def set(name, key, value) do
      Raft.write(name, {:set, key, value})
    end

    def get(name, key) do
      Raft.read(name, {:get, key})
    end

    def init(_name) do
      {:ok, @initial_state} 
    end

    def handle_write({:set, key, value}, state) do
      {{:ok, key, value}, put_in(state, [key], value)}
    end

    def handle_read({:get, key}, state) do
      case get_in(state, [key]) do
        nil ->
          {{:error, :key_not_found}, state}
        value ->
          {{:ok, value}, state}
      end
    end
  end
  ```

  Now we can start our peers:

  ```
  {:ok, _pid} = Raft.start_peer(KVStore, name: :s1)
  {:ok, _pid} = Raft.start_peer(KVStore, name: :s2)
  {:ok, _pid} = Raft.start_peer(KVStore, name: :s3)
  ```

  Each node must be given a unique name within the cluster. At this point our
  nodes are started but they're all followers and don't know anything about each
  other. We need to set the configuration so that they can communicate:

  ```
  Raft.set_configuration(:s1, [:s1, :s2, :s3])
  ```

  Once this runs the peers will start an election and elect a leader. You can
  check the current leader like so:

  ```
  leader = Raft.leader(:s1)
  ```

  Once we have the leader we can read and write to our state machine:

  ```
  {:error, :key_not_found} = KVStore.get(leader, :foo)
  {:ok, :foo, :bar} = KVStore.write(leader, :foo, :bar)
  {:ok, :bar} = KVStore.read(leader, :foo)
  ```

  We can now shutdown our leader and ensure that a new leader has been elected
  and our state is replicated across all nodes:

  ```
  Raft.stop(leader)

  # wait for election...

  new_leader = Raft.leader(:s2)
  {:ok, :bar} = KVStore.read(new_leader, :foo)
  ```

  We now have a consistent, replicated key-value store.

  ### Failures and re-elections

  Networks disconnects and other failures will happen. If this happens the peers
  might elect a new leader. If this occurs you will see messages like this:

  ```
  {:error, :election_in_progress} = KVStore.get(leader, :foo)
  {:error, {:redirect, new_leader}} = KVStore.get(leader, :foo)
  ```

  ## State Machine Message Safety

  The commands sent to each state machine are opaque to the raft protocol. There
  is *no validation* done to ensure that the messages conform to what the user
  state machine expects. Also these logs are persisted. What this means is that
  if a message is sent that causes the user state machine to crash it will
  crash the raft process until a code change is made to the state machine. There
  is no mechanism for removing an entry from the log. Great care must be taken
  to ensure that messages don't "poison" the log and state machine.

  ## Log Storage

  The log and metadata store is persisted to disk using rocksdb. This allows us
  to use a well known and well supported db engine that also does compaction.
  The log store is built as an adapter so its possible to construct other adapters
  for persistence.

  ## Operations

  ### Forceful override

  It may be desirable to initialize a server, copy its log
  file to other servers, set the database id for each follower, and then add
  them to the cluster using the add_server rpc methods. This circumvents expensive
  install snapshot calls.

  ## Protocol Overview

  Raft is a complex protocol and all of the details won't be covered here.
  This is an attempt to cover the high level topics so that users can make more
  informed technical decisions.

  Key Terms:

  * Cluster - A group of peers. These peers must be explicitly set.

  * Peer - A server participating in the cluster. Peers route messages,
  participate in leader election and store logs.

  * Log - The log is an ordered sequence of entries. Each entry is replicated on
  each peer and we consider the log to be consistent if all peers in the
  cluster agree on the entries and their order. Each log contains a binary blob
  which is opaque to the raft protocol but has meaning in the users state machine.
  This log is persisted to the local file system.

  * Quorum - A majority of peers. In raft this is (2/n)+1. Using a quorum allows
  some number of peers to be unavailable during leader election or
  replication. 

  * Leader - At any time there will only be 1 leader in a cluster. All reads and
  writes and configuration changes must pass through the leader in order to 
  provide consistency. Its the leaders responsibility to replicate logs to all
  other members of the cluster.

  * Committed - A log entry is "committed" if the leader has replicated it to
  a majority of peers. Only committed entries are applied to the users state
  machine.

  Each peer can be in 1 of 3 states: follower, leader, or candidate. When a
  peer is started it starts in a follower state. If a follower does not receive
  messages within a random timeout it transitions to a candidate and starts a
  new election.

  During an election the candidate requests votes from all of the other peers.
  If the candidate receives enough votes to have a quorum then the candidate
  transitions to the leader state and informs all of the other peers that they
  are the new leader.

  The leader accepts all reads and writes for the cluster. If a write occurs
  then the leader creates a new log entry and replicates that entry to the other
  peers. If a peer's log is missing any entries then the leader will bring the
  peer up to date by replicating the missing entries. Once the new log entry
  has been replicated to a majority of peers, the leader "commits" the new entry
  and applies it to the users state machine. In order to provide consistent
  reads a leader must ensure that they still maintain a quorum. Before executing
  a read the leader will send a message to each follower and ensure that they
  are still the leader. This provides consistent views of the data but it also
  can have performance implications for read heavy operations.

  Each time the followers receive a message they reset their "election timeout".
  This process continues until a follower times out and starts a new election,
  starting the cycle again.
  """

  alias Raft.{
    Log,
    Server,
    Config,
    Configuration
  }
  require Logger

  @type peer :: atom() | {atom(), atom()}
  @type opts :: [
    {:name, peer()},
    {:config, Config.t},
  ]

  @doc """
  Starts a new peer with a given Config.t.
  """
  @spec start_peer(module(), opts()) :: {:ok, pid()} | {:error, term()}

  def start_peer(mod, opts) do
    name = Keyword.get(opts, :name)
    config = Keyword.get(opts, :config) || %Raft.Config{}
    do_start(name, mod, config)
  end

  @doc """
  Gracefully stops the node.
  """
  def stop_peer(name) do
    Raft.Server.Supervisor.stop_peer(name)
  end

  @doc """
  Initializes a new cluster. Under normal operations this should be the first
  command issued to create a new cluster. Once this operation is run the server
  will be the first server in a new cluster. It will transition to a follower
  state and then immediately elect itself as the leader. This command will block
  until server has declared itself the leader.

  This operation can be called on any server regardless of if that server is
  already part of an existing cluster. If the server already contains log
  data then these data will be preserved. But a new, unique database id
  will be created. This means that the server will no longer be able to
  communicate with the other servers despite sharing the original log index and
  terms. This may be necessary in the event that a majority of servers are
  irrevocably lost and an administrator needs to start healing the cluster.
  """
  def initialize_cluster(server, timeout \\ 3_000) do
    Raft.Server.initialize_cluster(server, UUID.uuid4(), timeout)
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
    Raft.Server.current_leader(name)
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
    configuration = Enum.map(configuration, &set_node/1)
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
    Raft.start_peer(Raft.StateMachine.Stack, name: {name, node()})
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

    {:ok, _s1} = Raft.start_peer(Raft.StateMachine.Echo, name: :s1, config: %Config{data_dir: path})
    {:ok, _s2} = Raft.start_peer(Raft.StateMachine.Echo, name: :s2, config: %Config{data_dir: path})
    {:ok, _s3} = Raft.start_peer(Raft.StateMachine.Echo, name: :s3, config: %Config{data_dir: path})

    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = Raft.set_configuration(:s1, nodes)

    {:s1, :s2, :s3}
  end

  defp do_start(nil, _, _), do: raise ArgumentError, "Must include a `:name` argument"
  defp do_start(name, mod, config) do
    Raft.Server.Supervisor.start_peer({name, node()}, %{config | state_machine: mod})
  end

  defp set_node(server) when is_atom(server), do: {server, node()}
  defp set_node(peer), do: peer

end
