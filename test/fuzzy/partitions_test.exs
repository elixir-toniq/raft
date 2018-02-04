defmodule Raft.Fuzzy.PartitionsTest do
  use ExUnit.Case, async: false
  import StreamData

  alias Raft.Support.{
    Applier,
    Cluster,
  }

  def commands, do: one_of([
    tuple({constant(:enqueue), term()}),
    constant(:dequeue),
  ])

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
      Application.stop(:raft)
    end

    :ok
  end

  test "node shutdowns" do
    # Start 5 node cluster
    cluster = Cluster.start(5)

    # wait for leader to be elected
    leader = Cluster.wait_for_election(cluster)
    IO.inspect(leader, label: "Got a leader")

    {:ok, applier} = Applier.start_link({cluster, commands()})
    :ok = Applier.start_applying(applier)

    for _ <- (0..10) do
      {shutdown, cluster} = Cluster.random_shutdown(cluster)

      # Sleep a bit
      :timer.sleep(2_000)

      # Heal
      Cluster.restart(cluster, shutdown)
    end

    {commands, _errors} = Applier.stop_applying(applier)
    IO.inspect(commands, label: "Commands after applying")
    Cluster.stop(cluster)

    assert Cluster.all_logs_match(cluster, commands)
    assert Cluster.all_fsms_match(cluster, commands)
  end

  @tag :skip
  test "leader partitions" do
    # Start 5 node cluster
    cluster = Cluster.start(5)

    # wait for leader to be elected
    leader = Cluster.wait_for_election(cluster)

    # Start sending messages to the leader in the cluster (handle any errors)
    cluster = Cluster.apply_commands(cluster, leader, commands(), 10)

    # start partitioning the leader and some followers
    for _ <- (0..10) do

    end
    # Sleep a bit
    # Heal

    Cluster.stop(cluster)

    # Check all logs
    assert Cluster.all_logs_match(cluster)
    # Check all fsm state
    assert Cluster.all_fsms_match(cluster)

    # Report the command sequence if there was a failure
    # IO.puts Cluster.report(cluster)
  end
end
