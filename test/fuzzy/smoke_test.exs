defmodule PropCheck.Test.PingPongStateM do
  @moduledoc """
  State machine for property testing the ping pong player interaction.
  The properties are called from the test script `ping_pong_test.exs`.
  """

  use PropCheck.StateM
  use PropCheck
  use ExUnit.Case
  alias PropCheck.Test.PingPongMaster
  require Logger
  @moduletag capture_log: true

  property "ping-pong playing works fine", [:verbose] do
    numtests(3_000, forall cmds in commands(__MODULE__) do
      trap_exit do
        kill_all_player_processes()
        PingPongMaster.start_link()
        #:ok = :sys.trace(PingPongMaster, true)
        r = run_commands(__MODULE__, cmds)
        {history, state, result} = r
        PingPongMaster.stop
        wait_for_master_to_stop()
        #IO.puts "Property finished. result is: #{inspect r}"
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

  defp wait_for_master_to_stop() do
    ref = Process.monitor(PingPongMaster)
    receive do
      {:DOWN, ^ref, :process, _object, _reason} -> :ok
    end
  end


  # ensure all player processes are dead
  defp kill_all_player_processes() do
    Process.registered
    |> Enum.filter(&(Atom.to_string(&1) |> String.starts_with?("player_")))
    |> Enum.each(fn name ->
      # nice idea from José Valim: Monitor the process ...
      ref = Process.monitor(name)
      pid = Process.whereis(name)
      if is_pid(pid) and Process.alive?(pid) do
        try do
          Process.exit(pid, :kill)
        catch
          _what, _value -> Logger.debug "Already killed process #{name}"
        end
      end
      # ... and wait for the DOWN message.
      receive do
        {:DOWN, ^ref, :process, _object, _reason} -> :ok
      end
    end)
  end

  #####################################################
  ##
  ## The state machine: We test playing, our model
  ## is a set of registered names and their scores.
  ##
  #####################################################

  defstruct players: [],
    scores: %{}

  #####################################################
  ##
  ## Value Generators
  ##
  #####################################################
  @max_players 100
  @players 1..@max_players |> Enum.map(&("player_#{&1}") |> String.to_atom)

  def name(), do: elements @players
  def name(%__MODULE__{players: player_list}), do: elements player_list

  def command(%__MODULE__{players: []}), do:
    {:call, PingPongMaster, :add_player, [name()]}
  def command(state) do
    oneof([
      {:call, PingPongMaster, :add_player, [name()]},
      {:call, PingPongMaster, :remove_player, [name(state)]},
      {:call, PingPongMaster, :get_score, [name(state)]},
      {:call, PingPongMaster, :play_ping_pong,[name(state)]},
      {:call, PingPongMaster, :play_tennis,[name(state)]},
      {:call, PingPongMaster, :play_football,[name(state)]}
      ])
  end

  #####################################################
  ##
  ## The state machine: state transitions.
  ##
  #####################################################


  @doc "initial model state of the state machine"
  def initial_state(), do: %__MODULE__{}

  @doc """
  Update the model state after a successful call. The `state` parameter has
  the value of before the call, `value` is the return value of the `call`, such
  that the new state can depend on the old state and the returned value.
  """
  def next_state(s, _value, {:call, PingPongMaster, :add_player, [name]}) do
    case s.players |> Enum.member?(name) do
      false -> %__MODULE__{s |
          players: [name | s.players],
          scores: s.scores |> Map.put(name, 0)}
      true  -> s
    end
  end
  def next_state(s, _value, {:call, PingPongMaster, :remove_player, [name]}) do
    %__MODULE__{s |
      players: s.players |> List.delete(name),
      scores: s.scores |> Map.delete(name)}
  end
  def next_state(s, _value, {:call, PingPongMaster, :play_ping_pong, [name]}) do
    %__MODULE__{s |
      scores: s.scores |> Map.update!(name, &(&1 + 1))}
  end
  def next_state(state, _value, _call), do: state

  @doc "can the call in the current state be made?"
  def precondition(s, {:call, PingPongMaster, do_it, [name]}) when
    do_it in [:remove_player, :play_tennis, :play_ping_pong, :get_score]
  do
    s.players |> Enum.member?(name)
  end
  def precondition(_state, _call),  do: true

  @doc """
  Checks that the model state after the call is proper. The `state` is
  the state *before* the call, the `call` is the symbolic call and `r`
  is the result of the actual call.
  """
  def postcondition(_s, {:call, PingPongMaster, :remove_player, [name]}, {:removed, n}), do: n == name
  def postcondition(_s, {:call, PingPongMaster, :add_player, [_name]}, :ok), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_ping_pong, [_name]}, :ok), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_tennis, [_name]}, :maybe_later), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_football, [_name]}, :no_way), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_ping_pong, [name]}, {:dead_player, name}), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_tennis, [name]}, {:dead_player, name}), do: true
  def postcondition(_s, {:call, PingPongMaster, :play_football, [name]}, {:dead_player, name}), do: true
  def postcondition(s, {:call, PingPongMaster, :get_score, [name]}, result), do:
    # playing ping pong is asynchronuous, therefore the counter in scores
    # might not be updated properly: our model is eager (and synchronous), but
    # the real machinery might be updated later
    result <= s.scores |> Map.fetch!(name)
  def postcondition(s, {:call, _, f, _}, r) do
    IO.puts "Failing postcondition for call #{f} with result #{inspect r} in state #{inspect s}"
    false
  end

    # IO.puts "postcondition: remove player #{name} => #{inspect r} in state: #{inspect players}"

end
