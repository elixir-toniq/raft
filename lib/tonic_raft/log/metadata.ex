defmodule Raft.Log.Metadata do
  @moduledoc """
  This module defines the metadata for a raft node. This data is persisted to
  disk as described in the paper.
  """

  @typedoc """
  Latest term the server has seen. Defaults to 0 on boot and increases
  monotonically.
  """
  @type current_term :: non_neg_integer()

  @typedoc """
  The candidate id that was voted for this term. Defaults to :none if there
  has been no vote this term.
  """
  @type voted_for :: :none | atom()

  @typedoc """
  Metadata struct.
  """
  @type t :: %__MODULE__{
    term: current_term(),
    voted_for: voted_for(),
  }

  defstruct term: 0, voted_for: :none
end
