defmodule TonicRaft.Fuzzy.SystemTest do
  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case
  require Logger
  @moduletag capture_log: true

  property "The system behaves correctly", [:verbose] do
    numtests(100, forall cmds in commands(__MODULE__) do
      trap_exit do
        clean()
        Application.ensure_all_started(:tonic_raft)

        {history, state, result} = run_commands(__MODULE__, cmds)

        for n <- state.running do
          TonicRaft.stop_node(n)
        end

        clean()

        Application.stop(:tonic_raft)

        (result == :ok)
        |> when_fail(
            IO.puts """
            History: #{inspect history, pretty: true}
            State: #{inspect state, pretty: true}
            Result: #{inspect result, pretty: true}
            """)
        |> aggregate(command_names cmds)
      end
    end)
  end

  # State machine
  defstruct [
    state: :init,
    running: [],
    old_servers: [],
    new_servers: [],
    commit_index: 0,
    last_committed_op: nil,
    leader: nil,
    to: nil,
  ]

  def clean do
    :tonic_raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)
  end

  def default_config do
    %TonicRaft.Config{
      state_machine: TonicRaft.Support.EchoFSM,
    }
  end

  def start_nodes(nodes) do
    for n <- nodes do
      start_node(n)
    end
  end

  def start_node(n) do
    # IO.puts "Starting node: #{inspect n}"
    # {:ok, _} = TonicRaft.start_node(n, default_config())
    TonicRaft.start_node(n, default_config())
  end

  #
  # Generators
  #

  def command(%{state: :init}) do
    {:call, __MODULE__, :start_nodes, [servers()]}
  end

  def command(%{state: :blank, to: to, running: running}) do
    call(:set_configuration, [to, running])
  end

  def command(%{state: :stable, old_servers: old, running: running})
    when length(running) <= div(length(old), 2) do
    to_start = oneof(old -- running)
    call(:start_node, [to_start])
  end

  def command(%{state: :stable, to: to, running: running}) do
    frequency([{100, call(:write, [to, command()])},
               {1,   call(:stop_node, [oneof(running)])}])
  end

  def servers do
    such_that ss <- oneof([three_servers(), five_servers(), seven_servers()]),
      when: Enum.count(Enum.uniq(ss)) == Enum.count(ss)
  end

  def server, do: oneof([:a, :b, :c, :d, :e, :f, :g, :h, :i])

  def three_servers, do: vector(3, server())

  def five_servers, do: vector(5, server())

  def seven_servers, do: vector(7, server())

  def command, do: oneof(["inc key val", "get key", "set key val"])

  #
  # State Transitions
  #

  def initial_state, do: %__MODULE__{}

  def precondition(%{state: :init}, _), do: true

  def precondition(%{running: []}, {:call, TonicRaft, _, _}), do: false

  def precondition(%{running: running}, {:call, TonicRaft, _, [to]}) do
    Enum.member?(running, to)
  end

  def precondition(%{running: running}, {:call, TonicRaft, op, [to, _]}) do
    case op do
      :write ->
        Enum.member?(running, to)
      :set_configuration ->
        Enum.member?(running, to)
    end
  end


  def next_state(%{state: :init}=s, _, {:call, __MODULE__, :start_nodes, [nodes]}) do
    leader = Enum.at(nodes, 0)
    %{s | state: :blank, running: nodes, to: leader, leader: leader}
  end

  def next_state(%{state: :blank, to: to, running: running}=s, _,
                 {:call, TonicRaft, :set_configuration, [to, running]}) do
    %{s | commit_index: 1, state: :stable, old_servers: running}
  end

  # def next_state(%{state: :stable, commit_index: ci, leader: leader, last_committed_op: last_op}=s,
  def next_state(%{state: :stable}=s, result, {:call, TonicRaft, :write, [_, op]}) do
    %{s |
      commit_index: call_self(:maybe_increment, [s.commit_index, result]),
      leader: call_self(:maybe_change_leader, [s.leader, result]),
      last_committed_op: call_self(:maybe_change_last_op, [s.last_committed_op, op, result]),
    }
  end

  def next_state(%{state: :stable, to: to, running: running}=s, _,
                 {:call, TonicRaft, :stop_node, [peer]}) do
    running = List.delete(running, peer)

    case to do
      ^peer ->
        %{s | leader: :unknown, running: running, to: Enum.at(running, 0)}

      _ ->
        %{s | running: running}
    end
  end

  # Figure out how to add an invariant here that ensures the indexes are monotonic
  # and that comitted entries always exist in the log

  def postcondition(%{state: :init}, {:call, __MODULE__, :start_nodes, _}, _) do
    true
  end

  def postcondition(%{state: :blank}, {:call, TonicRaft, :set_configuration, [_, _]}, {:ok, _}) do
    true
  end

  def postcondition(%{state: :stable, old_servers: old, to: to}, {:call, TonicRaft, :write, [to, _]}, 
                    {:ok, _}) do
    Enum.member?(old, to)
  end

  def postcondition(%{state: :stable, to: to}, {:call, TonicRaft, :write, [to, _]},
                    {:error, {:redirect, leader}}) do
    leader != to
  end

  def postcondition(%{state: :stabel, to: to}, {:call, TonicRaft, :write, [to, ]},
                    {:error, :election_in_progress}) do
    true
  end

  def postcondition(%{state: :stable}, {:call, TonicRaft, :stop_node, [_node]}, :ok) do
    true
  end


  #
  # Helper Functions
  #

  def maybe_increment(ci, {:ok, _}), do: ci + 1
  def maybe_increment(ci, {:error, _}), do: ci
  def maybe_increment(ci, result) do
    IO.puts "I got an increment with some nonsense: #{inspect result}"
  end

  def maybe_change_leader(leader, {:ok, _}), do: leader
  def maybe_change_leader(_, {:error, {:redirect, leader}}), do: leader
  def maybe_change_leader(_, {:error, _}), do: :unknown

  def maybe_change_last_op(_, op, {:ok, _}), do: op
  def maybe_change_last_op(last_op, _, {:error, _}), do: last_op

  defp call(cmd, args) do
    {:call, TonicRaft, cmd, args}
  end

  def call_self(cmd, args) do
    {:call, __MODULE__, cmd, args}
  end

  #
  # Invariants
  #

  def commit_indexes_are_monotonic(%{commit_index: ci}, state) do
    state.commit_index <= ci
  end

  def committed_entry_exists_in_log(%{commit_index: 0}, _) do
    true
  end

  def committed_entry_exists_in_log(%{leader: :unknown}, _) do
    true
  end

  def committed_entry_exists_in_log(%{commit_index: ci, last_committed_op: op}, to) do
    {:ok, %{type: type, data: cmd, index: commit_index}} = TonicRaft.get_entry(to, ci)

    case type do
      :config ->
        true

      :command ->
        commit_index == ci && cmd == op
    end
  end
end
