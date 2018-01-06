defmodule TonicLeader.ConfigurationTest do
  use ExUnit.Case, async: true

  alias TonicLeader.{Configuration, Log}
  alias TonicLeader.Configuration.Server

  describe "restore/1" do
    test "rebuilds the configuration from logs" do
      servers = [
        %Server{name: :s1, address: :foo, suffrage: :voter},
        %Server{name: :s2, address: :bar, suffrage: :voter},
      ]
      configuration = %Configuration{
        servers: servers,
        index: 1,
      }
      logs = [Log.configuration(1, 1, configuration)]
      configuration = Configuration.restore(logs)

      assert configuration.servers == servers
      assert configuration.index   == 1
      # assert configuration.latest  = %{}
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
end
