defmodule TonicRaft.ConfigurationTest do
  use ExUnit.Case, async: true

  alias TonicRaft.{Configuration}

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
