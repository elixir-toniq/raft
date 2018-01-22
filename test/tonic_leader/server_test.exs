defmodule TonicRaft.ServerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  def non_negative_integer, do: StreamData.sized(fn size -> integer(0..size) end)

  describe "up_to_date?/4" do
    property "determines if the log is up to date by term and index" do
      check all term_a <- non_negative_integer(),
                term_b <- non_negative_integer(),
                index_a <- non_negative_integer(),
                index_b <- non_negative_integer() do
        result = TonicRaft.Server.up_to_date?(term_a, index_a, term_b, index_b)
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
