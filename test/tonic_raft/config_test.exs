defmodule TonicRaft.ConfigTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias TonicRaft.Config

  property "election_timeout/1 returns values between the min and max" do
    check all min <- StreamData.positive_integer(),
              max <- StreamData.positive_integer() do
      try do
        Config.election_timeout(%{
          min_election_timeout: min,
          max_election_timeout: max
        })
      catch
        value -> assert value == :min_equals_max
      else
        timeout ->
          assert min <= timeout && timeout <= max
      end
    end
  end
end
