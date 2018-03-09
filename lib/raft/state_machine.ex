defmodule Raft.StateMachine do
  @moduledoc """
  This module provides a behaviour that can be implemented by clients to make
  use of the replicated log.
  """

  @type name :: Raft.peer()

  @typedoc """
  The value to return to client after completing a read or write.
  """
  @type val() :: any()

  @typedoc """
  The state for the state machine.
  """
  @type state() :: any()

  @typedoc """
  The read or write command.
  """
  @type cmd() :: any()

  @doc """
  Called when the state machine is initialized.
  """
  @callback init(name()) :: state()

  @doc """
  Called whenever there has been a committed write command.
  """
  @callback handle_write(cmd(), state()) :: {val(), state()}

  @doc """
  Called when the leader has established that they still have a majority and
  haven't been deposed as described in the raft paper section 8. While it is
  possible to change the state here it is HIGHLY discouraged. Changes during a
  read will NOT be persisted or replicated to other servers. Any mutations done
  here will be lost after a crash recovery or when starting a new server.
  """
  @callback handle_read(cmd(), state()) :: val() | {val(), state()}

  defmacro __using__(_) do
    caller = __CALLER__.module
    quote location: :keep do
      @behaviour unquote(__MODULE__)

      def child_spec(args) do
        app = Application.get_application(unquote(caller))
        name = Keyword.get(args, :name, unquote(caller))
        data_dir =
          case Keyword.get(args, :data_dir) do
            nil ->
              # Default to a unique data dir for each node and state machine
              node_str = "#{Node.self}"
              root_dir = Application.app_dir(app, "data")
              Path.join([root_dir, node_str, "#{name}"])
            dir ->
              dir
          end
        File.mkdir_p!(data_dir)
        config =
          args
          |> Keyword.put(:name, name)
          |> Keyword.put(:data_dir, data_dir)
          |> Raft.Config.new()
          |> Map.put(:state_machine, unquote(caller))
        peer_name = {name, Node.self}
        child_id = {Raft.PeerSupervisor, name}
        Supervisor.child_spec({Raft.PeerSupervisor, {peer_name, config}}, id: child_id)
      end

      defoverridable [child_spec: 1]
    end
  end
end
