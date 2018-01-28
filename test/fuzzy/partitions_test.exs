defmodule TonicRaft.Fuzzy.PartitionsTest do
  use ExUnit.Case, async: false
  import StreamData

  alias TonicRaft.Support.Cluster

  def commands, do: one_of([
    tuple({constant(:enqueue), term()}),
    constant(:dequeue),
  ])

  setup do
    Application.ensure_all_started(:tonic_raft)

    :tonic_raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    on_exit fn ->
      Application.stop(:tonic_raft)
    end

    :ok
  end


  test "leader partitions" do
    # Start 5 node cluster
    cluster = Cluster.start(5)

    # wait for leader to be elected
    leader = Cluster.wait_for_election(cluster)

    # Start sending messages to the leader in the cluster (handle any errors)
    cluster = Cluster.apply_commands(cluster, leader, commands(), 10)

    # start partitioning the leader and some followers
    # Sleep a bit
    # Heal

    # Check all logs
    # Check all fsm state

    # Report the command sequence if there was a failure
    IO.puts Cluster.report(cluster)
  end
end
