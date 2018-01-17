defmodule TonicLeader.ConfigurationTest do
  use ExUnit.Case, async: true

  alias TonicLeader.{Configuration, Log}
  alias TonicLeader.Configuration.Server

  # describe "restore/1" do
  #   test "rebuilds the configuration from logs" do
  #     servers = [
  #       %{name: "s1", address: "foo", suffrage: "voter"},
  #       %{name: "s2", address: "bar", suffrage: "voter"},
  #     ]
  #     configuration = %Configuration{
  #       servers: servers,
  #       index: 1,
  #     }
  #     logs = [Log.configuration(1, 1, configuration)]
  #     configuration = Configuration.restore(logs)

  #     assert configuration.servers == servers
  #     assert configuration.index   == 1
  #   end

  #   test "defaults if there are no logs" do
  #     logs = []
  #     configuration = Configuration.restore(logs)

  #     assert configuration.servers == []
  #     assert configuration.index   == 0
  #     assert configuration.latest  == %{}
  #   end

  #   test "filters out non config change logs" do

  #   end
  # end

  # describe "quorum/1" do
  #   test "returns the number of servers needed to have a majority" do
  #     configuration = %Configuration{
  #       servers: [
  #         %Server{name: :s1, address: :foo, suffrage: :voter},
  #         %Server{name: :s2, address: :bar, suffrage: :voter},
  #       ],
  #       index: 1,
  #     }

  #     assert Configuration.quorum(configuration) == 2

  #     configuration = %Configuration{
  #       servers: [
  #         %Server{name: :s1, address: :foo, suffrage: :voter},
  #         %Server{name: :s2, address: :bar, suffrage: :voter},
  #         %Server{name: :s3, address: :baz, suffrage: :voter},
  #       ],
  #       index: 1,
  #     }
  #     assert Configuration.quorum(configuration) == 2

  #     configuration = %Configuration{
  #       servers: [
  #         %Server{name: :s1, address: :foo, suffrage: :voter},
  #         %Server{name: :s2, address: :bar, suffrage: :voter},
  #         %Server{name: :s3, address: :baz, suffrage: :voter},
  #         %Server{name: :s4, address: :foo, suffrage: :staging},
  #         %Server{name: :s5, address: :bar, suffrage: :staging},
  #         %Server{name: :s6, address: :baz, suffrage: :voter},
  #       ],
  #       index: 1,
  #     }

  #     assert Configuration.quorum(configuration) == 3
  #   end
  # end

  describe "quorum_max/2" do
    test "returns the max index for which we have a quorum" do
      servers = [:s1, :s2, :s3, :s4, :s5]
      configuration = %Configuration{
        state: :stable,
        old_servers: servers,
      }

      indexes = %{s1: 1, s2: 3, s3: 3, s4: 3, s5: 2}

      assert Configuration.quorum_max(configuration, indexes) == 3

      indexes = %{s1: 1, s2: 2, s3: 4, s4: 3, s5: 2}
      assert Configuration.quorum_max(configuration, indexes) == 2

      indexes = %{s1: 1, s2: 1, s3: 1, s4: 0, s5: 0}
      assert Configuration.quorum_max(configuration, indexes) == 1
    end
  end
end
