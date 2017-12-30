defmodule TonicLeader.ServerTest do
  use ExUnit.Case, async: true

  alias TonicLeader.Server

  def start_cluster() do

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
      servers: [self()],
      election_timeout_min: 0,
      election_timeout_max: 1
    ])

    {:ok, s1} = Server.start_link(config)

    assert_received {:request_vote, 1}
  end

  # test "followers forward requests to leaders" do
  #   cluster = start_cluster(nodes: 3)

  #   assert lead = leader(cluster)
  #   assert followers(cluster)
  # end
end
