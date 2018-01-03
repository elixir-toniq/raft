defmodule TonicLeaderTest do
  use ExUnit.Case
  doctest TonicLeader

  alias TonicLeader.{Config, Configuration, Server}

  describe "bootstrap/2" do
    test "starts a new cluster" do
      configuration = %Configuration{
        servers: [
          Configuration.voter(:s1, node()),
          Configuration.voter(:s2, node()),
          Configuration.voter(:s3, node()),
        ],
      }
      {:ok, s1} = TonicLeader.bootstrap(%Config{name: :s1}, configuration)
      {:ok, s2} = TonicLeader.bootstrap(%Config{name: :s2}, configuration)
      {:ok, s3} = TonicLeader.bootstrap(%Config{name: :s3}, configuration)

      assert TonicLeader.leader(s1) == :none

      leader = wait_for_election([s1, s2, s3])

      assert TonicLeader.leader(s1) == leader
      assert TonicLeader.leader(s2) == leader
      assert TonicLeader.leader(s3) == leader
    end
  end

  def wait_for_election(servers) do
    case Enum.find(fn server -> Server.status(server).current_state == :leader end) do
      nil ->
        :timer.sleep(20)
        wait_for_election(servers)
      leader ->
        leader
    end
  end
end

