defmodule PropCheck.Test.PingPongMaster do
  @moduledoc """
  This is the ping pong master from Proper's Process Interaction Tutorial,
  translated from Erlang to Elixir.

  From the tutorial introduction:

  In this tutorial, we will use PropEr to test a group of interacting processes.
  The system under test consists of one master and multiple slave processes.
  The main concept is that the master plays ping-pong (i.e. exchanges ping and
  pong messages) with all slave processes, which do not interact with each other.
  For the rest of this tutorial, we will refer to the slave processes as
  the ping-pong players.

  """

  use GenServer
  require Logger

  # -------------------------------------------------------------------
  # Master's API
  # -------------------------------------------------------------------

  def start_link() do
    GenServer.start_link(__MODULE__, [], [name: __MODULE__])
  end

  def stop() do
    ref = Process.monitor(__MODULE__)
    try do
      GenServer.cast(__MODULE__, :stop)
    catch
      :error, :badarg -> Logger.error "already_dead_master:  #{__MODULE__}"
    end
    receive do
      {:DOWN, ^ref, :process, _object, _reason} -> :ok
    end
  end

  def add_player(name) do
    GenServer.call(__MODULE__, {:add_player, name})
  end

  def remove_player(name) do
    GenServer.call(__MODULE__, {:remove_player, name})
  end

  def ping(from_name) do
    #Logger.debug "Ping Pong Game for #{inspect from_name}"
    r = GenServer.call(__MODULE__, {:ping, from_name})
    #Logger.debug "Ping Pong result: #{inspect r}"
    r
  end

  def get_score(name) do
    GenServer.call(__MODULE__, {:get_score, name})
  end

  # -------------------------------------------------------------------
  # Player's internal loop
  # -------------------------------------------------------------------

  @doc "Process loop for the ping pong player process"
  def ping_pong_player(name, counter \\ 1) do
    #Logger.debug "Player #{inspect name} is waiting round #{counter}"
    receive do
      :ping_pong        -> # Logger.debug "Player #{inspect name} got a request for a ping-pong game"
          ping(name)
      {:tennis, from}   -> send(from, :maybe_later)
      {:football, from} -> send(from, :no_way)
      msg -> Logger.error "Player #{inspect name} got invalid message #{inspect msg}".
        exit(:kill)
    end
    # Logger.debug "Player #{inspect name} is recursive"
    ping_pong_player(name, counter + 1)
  end

  # -------------------------------------------------------------------
  # Player's API
  # -------------------------------------------------------------------

  @doc "Start playing ping pong"
  @spec play_ping_pong(atom) :: :ok | {:dead_player, atom}
  def play_ping_pong(player) do
    robust_send(player, :ping_pong)
  end

  @doc "Start playing football"
  def play_football(player) do
    case robust_send(player, {:football, self()}) do
      :ok ->
        receive do
          reply -> reply
          after 500 -> "Football timeout!"
        end
      return -> return
    end
  end

  @doc "Start playing football"
  def play_football_eager(player) do
    send(player, {:football, self()})
    receive do
      reply -> reply
    after 500 -> "Football timeout!"
    end
  end

  @doc "Start playing tennis"
  def play_tennis(player) do
    case robust_send(player, {:tennis, self()}) do
      :ok ->
        receive do
          reply -> reply
          after 500 -> "Tennis timeout!"
        end
      return -> return
    end
  end

  defp robust_send(name, msg) do
    try do
      send(name, msg)
      :ok
    catch
      :error, :badarg -> {:dead_player, name}
    end
  end

  # -------------------------------------------------------------------
  # Callbacks
  # -------------------------------------------------------------------

  def init([]) do
    {:ok, %{}}
  end

  def handle_cast(:stop, scores) do
    {:stop, :normal, scores}
  end

  def handle_call({:add_player, name}, _from, scores) do
    case Map.fetch(scores, name) do
      :error ->
          pid = spawn(fn() -> ping_pong_player(name) end)
          true = Process.register(pid, name)
          {:reply, :ok, scores |> Map.put(name, 0)}
      {:ok, _} ->
          Logger.debug "add_player: player #{name} already exists!"
          {:reply, :ok, scores}
    end
  end
  def handle_call({:remove_player, name}, _from, scores) do
    case Process.whereis(name) do
      nil -> Logger.debug("Process #{name} is unknown / not running")
      pid -> kill_process(pid)
    end
    # Process.whereis(name) |> Process.exit(:kill)
    {:reply, {:removed, name}, scores |> Map.delete(name)}
  end
  def handle_call({:ping, from_name}, _from, scores) do
    # Logger.debug "Master: Ping Pong Game for #{inspect from_name}"
    if (scores |> Map.has_key?(from_name)) do
      {:reply, :pong, scores |> Map.update!(from_name, &(&1 + 1))}
    else
      {:reply, {:removed, from_name}, scores}
    end
  end
  def handle_call({:get_score, name}, _from, scores) do
    {:reply, scores |> Map.fetch!(name), scores}
  end

  @doc "Terminates all clients"
  def terminate(_reason, scores) do
    # Logger.info "Terminate Master with scores #{inspect scores}"
    scores
      |> Map.keys
      |> Enum.each(&kill_process(&1))
  end

  defp kill_process(pid) when is_pid(pid) do
    # monitoring works for already killed processes
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)
    # ... and wait for the DOWN message.
    receive do
      {:DOWN, ^ref, :process, _object, _reason} -> :ok
    end
  end
  defp kill_process(name) do
    kill_process(Process.whereis(name))
  end
end
