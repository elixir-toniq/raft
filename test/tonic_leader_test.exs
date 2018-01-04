defmodule TonicLeaderTest do
  use ExUnit.Case
  doctest TonicLeader

  alias TonicLeader.{Config, Configuration, Server}

  setup do
    :tonic_leader
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    :ok
  end

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

      assert TonicLeader.Server.leader(s1) == :none

      leader = wait_for_election([s1, s2, s3])

      assert TonicLeader.Server.leader(s1) == leader
      assert TonicLeader.Server.leader(s2) == leader
      assert TonicLeader.Server.leader(s3) == leader
    end
  end

  def wait_for_election(servers) do
    case Enum.find(servers, fn server -> Server.status(server).current_state == :leader end) do
      nil ->
        :timer.sleep(200)
        wait_for_election(servers)
      leader ->
        leader
    end
  end
end

