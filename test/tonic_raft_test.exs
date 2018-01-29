defmodule TonicRaftTest do
  use ExUnit.Case
  doctest TonicRaft

  alias TonicRaft.{Config, Server}

  defmodule StackTestFSM do
    @behaviour TonicRaft.StateMachine

    def init(_) do
      []
    end

    def handle_read(:length, stack) do
      {Enum.count(stack), stack}
    end

    def handle_read(:all, stack) do
      {stack, stack}
    end

    def handle_write({:enqueue, item}, stack) do
      new_stack = [item | stack]
      {Enum.count(new_stack), new_stack}
    end

    def handle_write(:dequeue, [item | stack]) do
      {item, stack}
    end

    def handle_write(:dequeue, []) do
      {:empty, []}
    end
  end

  setup do
    :tonic_raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    on_exit fn ->
      for s <- [:s1, :s2, :s3] do
        TonicRaft.stop_node(s)
      end
    end

    :ok
  end

  test "starting a cluster" do
    # Start each node individually with no configuration. Each node will
    # come up as a follower and remain there since they have no known
    # configuration yet.
    {:ok, _s1} = TonicRaft.start_node(:s1, %Config{state_machine: StackTestFSM})
    {:ok, _s2} = TonicRaft.start_node(:s2, %Config{state_machine: StackTestFSM})
    {:ok, _s3} = TonicRaft.start_node(:s3, %Config{state_machine: StackTestFSM})

    # Tell a server about other nodes
    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = TonicRaft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)

    assert TonicRaft.leader(:s1) == :s1
    assert TonicRaft.leader(:s2) == :s1
    assert TonicRaft.leader(:s3) == :s1
  end

  test "log replication with 3 servers" do
    {:ok, _s1} = TonicRaft.start_node(:s1, %Config{state_machine: StackTestFSM})
    {:ok, _s2} = TonicRaft.start_node(:s2, %Config{state_machine: StackTestFSM})
    {:ok, _s3} = TonicRaft.start_node(:s3, %Config{state_machine: StackTestFSM})

    # Tell a server about other nodes
    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = TonicRaft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)

    assert TonicRaft.leader(:s1) == :s1
    assert TonicRaft.leader(:s2) == :s1
    assert TonicRaft.leader(:s3) == :s1

    assert {:ok, 1}     = TonicRaft.write(:s1, {:enqueue, 1})
    assert {:ok, 2}     = TonicRaft.write(:s1, {:enqueue, 2})
    assert {:ok, 2}     = TonicRaft.write(:s1, :dequeue)
    assert {:ok, 2}     = TonicRaft.write(:s1, {:enqueue, 4})
    assert {:ok, [4,1]} = TonicRaft.read(:s1, :all)

    # Ensure that the messages are replicated to all servers
    #
    # Ensure that the fsms all have logs applied
  end

  test "commands sent to followers should redirect to leader" do
    flunk "Not Implemented"
  end

  test "commands sent to candidates should error" do
    flunk "Not Implemented"
  end

  test "leader failure" do
    # Start all nodes
    {:ok, _s1} = TonicRaft.start_node(:s1, %Config{state_machine: StackTestFSM})
    {:ok, _s2} = TonicRaft.start_node(:s2, %Config{state_machine: StackTestFSM})
    {:ok, _s3} = TonicRaft.start_node(:s3, %Config{state_machine: StackTestFSM})

    nodes = [:s1, :s2, :s3]
    {:ok, _configuration} = TonicRaft.set_configuration(:s1, nodes)

    # Ensure that s1 has been elected leader which means our configuration has
    # been shared throughout the cluster.
    _ = wait_for_election(nodes)
    assert TonicRaft.leader(:s1) == :s1
    assert TonicRaft.leader(:s2) == :s1
    assert TonicRaft.leader(:s3) == :s1

    # Disconnect the leader from the cluster
    TonicRaft.stop_node(:s1)

    # Wait until a new leader is elected
    leader = wait_for_election([:s2, :s3])

    # leader = leader(cluster)

    # Ensure the current term is greater

    # Apply should not work on old leader

    # Apply should work on new leader
    assert {:ok, 1} = TonicRaft.write(leader, {:enqueue, 1})

    # Reconnect the leader
    TonicRaft.start_node(:s1, %Config{state_machine: StackTestFSM})

    # Ensure that the fsms all have the same content
    assert {:ok, 1} = TonicRaft.write(leader, :dequeue)

    last_index = TonicRaft.status(leader).last_index

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
    case TonicRaft.status(server) do
      %{last_index: ^index} ->
        true

      _ ->
        :timer.sleep(100)
        wait_for_replication(server, index)
    end
  end
end

