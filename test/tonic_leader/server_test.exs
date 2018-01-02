defmodule TonicLeader.ServerTest do
  use ExUnit.Case, async: true

  alias TonicLeader.{Server, Config}

  setup do
    for name <- ["s1", "s2", "s3"] do
      :tonic_leader
      |> Application.app_dir
      |> Path.join("#{name}.tonic")
      |> File.rm_rf
    end

    :ok
  end

  def start_cluster() do
    {:ok, foo} = Server.start_link(name: :foo)
    {:ok, bar} = Server.start_link(name: :bar)
    {:ok, baz} = Server.start_link(name: :baz)
  end

  test "all servers start in follower state" do
    {:ok, s1} = Server.start_link()
    {:ok, s2} = Server.start_link()

    assert Server.current_state(s1) == :follower
    assert Server.current_state(s2) == :follower
  end

  test "get/2 returns a value correctly" do
    {:ok, s1} = Server.start_link()

    assert Server.get(s1, :foo) == nil
  end

  test "put/3 puts a value at a key" do
    {:ok, s1} = Server.start_link()

    Server.put(s1, :foo, :bar)
    assert Server.get(s1, :foo) == :bar
  end

  test "Followers start an election if they don't receive rpcs within the timeout" do
    config = Config.new([
      members: [self()],
      election_timeout_min: 0,
      election_timeout_max: 1
    ])

    {:ok, _s1} = Server.start_link(config)

    assert_received {:request_vote, 1}
  end

  @tag :focus
  test "Servers can join a cluster" do
    {:ok, s1} = Server.bootstrap(Config.new([
      name: :s1
    ]))

    {:ok, s2} = Server.start_link([name: :s2])

    :ok = Server.add_voter(s1, :s2, s2)

    assert Server.status(s1) == %{members: [s2, s1]}
  end
end
