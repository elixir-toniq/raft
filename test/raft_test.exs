defmodule RaftTest do
  use ExUnit.Case
  doctest Raft

  alias Raft.{
    Server,
    StateMachine.Stack,
  }

  setup do
    Application.ensure_all_started(:raft)

    :raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    on_exit fn ->
      for s <- [:s1, :s2, :s3] do
        Raft.stop_peer(s)
      end
    end

    :ok
  end

  test "starting a cluster" do
    # Start each node individually with no configuration. Each node will
    # come up as a follower and remain there since they have no known
    # configuration yet.
    {:ok, _s1} = Raft.start_peer(Stack, name: :s1)
    {:ok, _s2} = Raft.start_peer(Stack, name: :s2)
    {:ok, _s3} = Raft.start_peer(Stack, name: :s3)

    # Tell a server about other nodes
    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = Raft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)

    assert Raft.leader(:s1) == :s1
    assert Raft.leader(:s2) == :s1
    assert Raft.leader(:s3) == :s1
  end

  test "log replication with 3 servers" do
    {:ok, _s1} = Raft.start_peer(Stack, name: :s1)
    {:ok, _s2} = Raft.start_peer(Stack, name: :s2)
    {:ok, _s3} = Raft.start_peer(Stack, name: :s3)

    # Tell a server about other nodes
    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = Raft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)

    assert Raft.leader(:s1) == :s1
    assert Raft.leader(:s2) == :s1
    assert Raft.leader(:s3) == :s1

    assert {:ok, 1}     = Raft.write(:s1, {:put, 1})
    assert {:ok, 2}     = Raft.write(:s1, {:put, 2})
    assert {:ok, 2}     = Raft.write(:s1, :pop)
    assert {:ok, 2}     = Raft.write(:s1, {:put, 4})
    assert {:ok, [4,1]} = Raft.read(:s1, :all)

    # Ensure that the messages are replicated to all servers
    #
    # Ensure that the fsms all have logs applied
  end

  @tag :focus
  test "leader failure" do
    # Start all nodes
    {:ok, _s1} = Raft.start_peer(Stack, name: :s1)
    {:ok, _s2} = Raft.start_peer(Stack, name: :s2)
    {:ok, _s3} = Raft.start_peer(Stack, name: :s3)

    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = Raft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)
    assert Raft.leader(:s1) == :s1
    assert Raft.leader(:s2) == :s1
    assert Raft.leader(:s3) == :s1

    # Disconnect the leader from the cluster
    Raft.stop_peer(:s1)

    # Wait until a new leader is elected
    leader = wait_for_election([:s2, :s3])

    # leader = leader(cluster)

    # Ensure the current term is greater

    # Apply should not work on old leader

    # Apply should work on new leader
    assert {:ok, 1} = Raft.write(leader, {:put, 1})

    # Reconnect the leader
    Raft.start_peer(Stack, name: :s1)

    # Ensure that the fsms all have the same content
    assert {:ok, 1} = Raft.write(leader, :pop)

    {:ok, %{last_index: last_index}} = Raft.status(leader)

    # Wait for replication to occur on all nodes
    wait_for_replication(:s1, last_index)
    wait_for_replication(:s2, last_index)
    wait_for_replication(:s3, last_index)

    # Ensure that there are 2 entries applied to all fsms
    {_, state} = :sys.get_state(:s1)
    assert state.state_machine_state == []
    {_, state} = :sys.get_state(:s2)
    assert state.state_machine_state == []
    {_, state} = :sys.get_state(:s3)
    assert state.state_machine_state == []
  end

  def wait_for_election(servers) do
    servers
    |> Enum.map(&Server.status/1)
    |> Enum.find(& &1.current_state == :leader)
    |> case do
      nil ->
        :timer.sleep(200)
        wait_for_election(servers)
      leader ->
        leader.name
    end
  end

  defp wait_for_replication(server, index) do
    case Raft.status(server) do
      {:ok, %{last_index: ^index}} ->
        true

      _ ->
        :timer.sleep(100)
        wait_for_replication(server, index)
    end
  end
end

