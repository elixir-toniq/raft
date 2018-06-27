defmodule Raft.ClusterConfigurationTest do
  use PropCheck.FSM
  use PropCheck
  use ExUnit.Case
  require Logger
  @moduletag capture_log: true
  @moduletag timeout: :infinity

  # Nodes are created without ids
  # When init is called on a single server it should be the only server in the
  # cluster.
  # After initialization a node should become a follower and then transition
  # to the leader state.
  # * Sets current_term to 0
  # * Generates uuid as a database id
  # * log needs to keep its current contents which may be nothing at all
  #
  # If init is called on an existing server in an existing cluster then that
  # server should maintain its logs, current term, and log index. But it should
  # have a new databaseId.
  #
  # AddServerRPC - Must include the existing databaseId or it must contain no data.
  # Otherwise reject it.
  #
  # SetDatabaseID - Sets the database id on a server. This allows clusters to be
  # initialized from existing log files.
  property "cluster initialization", [:verbose] do
    numtests(500, forall cmds in commands(__MODULE__) do
      trap_exit do
        clean()
        Application.ensure_all_started(:raft)

        {history, state, result} = run_commands(__MODULE__, cmds)

        # for n <- state.running do
        #   Raft.stop_peer(n)
        # end

        # clean()

        Application.stop(:raft)

        (result == :ok)
        |> aggregate(command_names cmds)
        |> when_fail(
            IO.puts """
            History: #{inspect history, pretty: true}
            State: #{inspect state, pretty: true}
            Result: #{inspect result, pretty: true}
            """)
      end
    end)
  end

  # State machine
  # defstruct [
  #   state: :init,
  #   running: [],
  #   old_servers: [],
  #   new_servers: [],
  #   commit_index: 0,
  #   last_committed_op: nil,
  #   to: :unknown,
  #   entries: [],
  # ]

  def clean do
    :raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)
  end

  def default_config do
    %Raft.Config{}
  end

  def start_nodes(nodes) do
    for n <- nodes do
      start_node(n)
    end
  end

  def start_node(n) do
    Raft.start_peer(Raft.StateMachine.Echo, name: n)
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
    call_self(:start_node, [to_start])
  end

  def command(%{state: :stable, to: to, running: running}) do
    frequency([{100, call(:write, [to, command()])},
               {20,   call(:stop_peer, [oneof(running)])}])
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

  def initial_state, do: %{state: :init}

  def precondition(%{state: :init}, {:call, Raft, _, _}), do: false

  def precondition(%{state: :init, old_servers: []}, {:call, _, :start_node, _}), do: false

  def precondition(%{state: :init}, _), do: true

  def precondition(%{state: :blank}, {:call, Raft, op, _}) do
    op == :set_configuration
  end

  def precondition(%{running: []}, {:call, Raft, _, _}), do: false

  def precondition(%{running: running}, {:call, Raft, :stop_peer, [to]}) do
    Enum.member?(running, to)
  end

  def precondition(%{old_servers: old, running: running}, {:call, _, :start_node, [to]}) do
    Enum.member?(old, to) && !Enum.member?(running, to)
  end

  def precondition(%{running: running}, {:call, Raft, op, [to, _]}) do
    case op do
      :write ->
        Enum.member?(running, to)

      :set_configuration ->
        Enum.member?(running, to)
    end
  end

  def next_state(%{state: :init}=s, _, {:call, __MODULE__, :start_nodes, [nodes]}) do
    leader = Enum.at(nodes, 0)
    %{s | state: :blank, running: nodes, to: leader}
  end

  def next_state(%{state: :blank, to: to, running: running}=s, _,
                 {:call, Raft, :set_configuration, [to, running]}) do
    %{s | commit_index: 1, state: :stable, old_servers: running}
  end

  def next_state(%{state: :stable}=s, op, {:call, Raft, :write, [_, op]}) do
    entries = [{s.commit_index+1, op} | s.entries]
    %{s | commit_index: s.commit_index + 1, last_committed_op: op, entries: entries}
  end
  def next_state(%{state: :stable}=s, {:error, e}, {:call, Raft, :write, [_, _op]}) do
    case e do
      {:redirect, :none} ->
        s

      {:redirect, leader} ->
        %{s | to: leader}

      :election_in_progress ->
        %{s | to: :unknown}
    end
  end
  def next_state(%{state: :stable}=s, _, {:call, Raft, :write, [_, _]}) do
    s
  end

  def next_state(%{state: :stable}=s, _, {:call, _, :start_node, [to]}) do
    %{s | running: [to | s.running]}
  end

  def next_state(%{state: :stable, to: to, running: running}=s, _,
                 {:call, Raft, :stop_peer, [peer]}) do
    running = List.delete(running, peer)
    cond do
      running == [] ->
        %{s | running: running, to: :unknown}

      to == peer ->
        new_leader = Enum.at(running, 0)
        %{s | running: running, to: new_leader}

      true ->
        %{s | running: running}
    end
  end

  def postcondition(%{state: :init}, {:call, __MODULE__, :start_nodes, _}, _) do
    true
  end

  def postcondition(%{state: :blank}, {:call, Raft, :set_configuration, [_, _]}, {:ok, _}) do
    true
  end

  def postcondition(%{state: :stable, old_servers: old, to: to}=s,
                    {:call, Raft, :write, [to, op]},
                    op) do
    {_, server_state} = :sys.get_state(to)
    Enum.member?(old, to) &&
    commit_indexes_are_monotonic(s.commit_index, server_state) &&
    committed_entry_exists_in_log(to, s.commit_index+1, op) &&
    committed_entry_was_replicated(s.running, s.commit_index+1, op)
  end

  def postcondition(%{state: :stable, entries: entries}=s,
                    {:call, Raft, :write, [to, _]},
                    {:error, {:redirect, leader}}) do
    to != leader
    # case leader do
    #   :none ->
    #     true

    #   _ ->
    #     IO.puts "Got a redirect"
    #     IO.inspect leader, label: "This is the new leader"
    #     Enum.member?(s.old_servers, leader)
    #     && leader != to
    #     && has_all_committed_entries?(leader, entries)
    # end
  end

  def postcondition(%{state: :stable, to: to}=s,
                    {:call, Raft, :write, [to, _]},
                    {:error, :election_in_progress}) do
    committed_entry_exists_in_log(s, to)
    true
  end

  def postcondition(%{state: :stable}=s, {:call, Raft, :stop_peer, [peer]}, :ok) do
    true
    # cond do
    #   peer == s.to ->
    #     true

    #   s.to == :unknown ->
    #     true

    #   !Enum.member?(s.running, s.to) && Enum.member?(s.old_servers, s.to) ->
    #     true

    #   true ->
    #     committed_entry_exists_in_log(s.to, s.commit_index, s.last_committed_op)
    # end
  end

  def postcondition(%{state: :stable}, {:call, _, :start_node, [_peer]}, {:ok, _}) do
    true
  end


  #
  # Helper Functions
  #

  def maybe_increment(ci, result) do
    case result do
      {:ok, _} -> ci + 1
      {:error, _} -> ci
    end
  end

  def maybe_change_leader(leader, {:ok, _}), do: leader
  def maybe_change_leader(_, {:error, {:redirect, leader}}) do
    leader
  end
  def maybe_change_leader(_, {:error, _}), do: :unknown

  def maybe_change_last_op(_, op, {:ok, _}), do: op
  def maybe_change_last_op(last_op, _, {:error, _}), do: last_op

  defp call(cmd, args) do
    {:call, Raft, cmd, args}
  end

  def call_self(cmd, args) do
    {:call, __MODULE__, cmd, args}
  end

  #
  # Invariants
  #

  def commit_indexes_are_monotonic(ci, state) do
    state.commit_index <= ci+1
  end

  def committed_entry_exists_in_log(peer, index, op) do
    {:ok, %{type: type, data: cmd, index: commit_index}} = Raft.get_entry(
      peer,
      index
    )

    case type do
      :config ->
        true

      :command ->
        commit_index == index && cmd == op
    end
  end
  def committed_entry_exists_in_log(%{commit_index: 0}, _) do
    true
  end

  def committed_entry_exists_in_log(%{to: :unknown}, _) do
    true
  end

  def committed_entry_exists_in_log(%{commit_index: ci, last_committed_op: op}, to) do
    {:ok, %{type: type, data: cmd, index: commit_index}} = Raft.get_entry(to, ci)

    case type do
      :config ->
        true

      :command ->
        commit_index == ci && cmd == op
    end
  end

  def committed_entry_was_replicated(servers, index, op) do
    servers
    |> Enum.map(& entry_exists?(&1, index, op))
    |> Enum.all?
  end

  defp entry_exists?(server, index, op) do
    case Raft.get_entry(server, index) do
      {:ok, %{type: :config}} ->
        true

      {:ok, %{type: :command, index: ^index, data: ^op}} ->
        true

      _ ->
        false
    end
  end

  defp has_all_committed_entries?(server, entries) do
    IO.puts "Checking that the leader has all the entries"
    IO.inspect [server, entries], label: "Checking entries"
    entries
    |> Enum.map(fn {index, op} -> entry_exists?(server, index, op) end)
    |> IO.inspect(label: "Does the entry exist?")
    |> Enum.all?
  end
end
