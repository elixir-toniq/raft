defmodule TonicLeader.FSM do
  @moduledoc """
  This module provides a behaviour that can be implemented by clients to make
  use of the replicated log.
  """

  # @callback handle_apply(log) :: :ok

  # @callback snapshot() :: :ok

  # @callback restore() :: :ok
end
