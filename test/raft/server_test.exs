defmodule Raft.ServerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Raft.Server

  def non_negative_integer, do: StreamData.sized(fn size -> integer(0..size) end)

  @tag :focus
  describe "initialize_cluster/2" do
    setup do
      :raft
      |> Application.app_dir
      |> File.cd!(fn ->
        File.ls!()
        |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
        |> Enum.map(&Path.relative_to_cwd/1)
        |> Enum.map(&File.rm_rf!/1)
      end)

      {:ok, _server} = Raft.start_peer(Raft.Support.EchoFSM, [
        store: Raft.Store.InMemory,
        name: __MODULE__
      ])

      {:ok, %{server: __MODULE__}}
    end

    test "resets the database_id for the cluster", %{server: server} do
      assert Server.get_database_id(server) == nil
      Server.initialize_cluster(server)
      assert {__MODULE__, _} = Server.current_leader(server)
      assert Server.get_database_id(server) != nil
    end

    test "retains any existing logs and current term", %{server: server} do
      flunk
    end
  end

  describe "up_to_date?/4" do
    property "determines if the log is up to date by term and index" do
      check all term_a <- non_negative_integer(),
                term_b <- non_negative_integer(),
                index_a <- non_negative_integer(),
                index_b <- non_negative_integer() do
        result = Raft.Server.up_to_date?(term_a, index_a, term_b, index_b)
        cond do
          term_a > term_b                        -> assert result == true
          term_a < term_b                        -> assert result == false
          term_a == term_b && index_a > index_b  -> assert result == true
          term_a == term_b && index_a < index_b  -> assert result == false
          term_a == term_b && index_a == index_b -> assert result == true
        end
      end
    end
  end
end
