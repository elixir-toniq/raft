defmodule TonicLeader.ConfigurationTest do
  use ExUnit.Case, async: true

  alias TonicLeader.{Configuration, Log}
  alias TonicLeader.Configuration.Server

  describe "restore/1" do
    test "rebuilds the configuration from logs" do
      servers = [
        %{name: "s1", address: "foo", suffrage: "voter"},
        %{name: "s2", address: "bar", suffrage: "voter"},
      ]
      configuration = %Configuration{
        servers: servers,
        index: 1,
      }
      logs = [Log.configuration(1, 1, configuration)]
      configuration = Configuration.restore(logs)

      assert configuration.servers == servers
      assert configuration.index   == 1
    end

    test "defaults if there are no logs" do
      logs = []
      configuration = Configuration.restore(logs)

      assert configuration.servers == []
      assert configuration.index   == 0
      assert configuration.latest  == %{}
    end

    test "filters out non config change logs" do

    end
  end

  describe "quorum/1" do
    test "returns the number of servers needed to have a majority" do
      configuration = %Configuration{
        servers: [
          %Server{name: :s1, address: :foo, suffrage: :voter},
          %Server{name: :s2, address: :bar, suffrage: :voter},
        ],
        index: 1,
      }

      assert Configuration.quorum(configuration) == 2

      configuration = %Configuration{
        servers: [
          %Server{name: :s1, address: :foo, suffrage: :voter},
          %Server{name: :s2, address: :bar, suffrage: :voter},
          %Server{name: :s3, address: :baz, suffrage: :voter},
        ],
        index: 1,
      }
      assert Configuration.quorum(configuration) == 2

      configuration = %Configuration{
        servers: [
          %Server{name: :s1, address: :foo, suffrage: :voter},
          %Server{name: :s2, address: :bar, suffrage: :voter},
          %Server{name: :s3, address: :baz, suffrage: :voter},
          %Server{name: :s4, address: :foo, suffrage: :staging},
          %Server{name: :s5, address: :bar, suffrage: :staging},
          %Server{name: :s6, address: :baz, suffrage: :voter},
        ],
        index: 1,
      }

      assert Configuration.quorum(configuration) == 3
    end
  end
end
