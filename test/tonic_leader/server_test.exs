defmodule TonicLeader.ServerTest do
  use ExUnit.Case, async: true

  alias TonicLeader.{Server, Config, Configuration}

  @tag :skip
  test "Servers can join a cluster" do
    {:ok, s1} = Server.bootstrap(Config.new([
      name: :s1
    ]))

    {:ok, s2} = Server.start_link([name: :s2])

    :ok = Server.add_voter(s1, :s2, s2)

    assert Server.status(s1) == %{members: [s2, s1]}
  end
end
