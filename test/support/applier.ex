defmodule Raft.Support.Applier do
  use GenServer

  alias Raft.Support.Cluster

  def start_link({cluster, generator}) do
    GenServer.start_link(__MODULE__, {cluster, generator})
  end

  def start_applying(pid) do
    GenServer.call(pid, :start_applying)
  end

  def stop_applying(pid) do
    GenServer.call(pid, :stop_applying)
  end

  def init({cluster, generator}) do
    state = %{
      applying: false,
      timer: nil,
      writes: [],
      errors: [],
      generator: generator,
      cluster: cluster,
    }
    {:ok, state}
  end

  def handle_call(:start_applying, _from, state) do
    timer = Process.send_after(self(), :send_more, 200)
    {:reply, :ok, %{state | timer: timer, applying: true}}
  end

  def handle_call(:stop_applying, _from, state) do
    Process.cancel_timer(state.timer)
    {:reply, {state.writes, state.errors}, %{state | applying: false}}
  end

  def handle_info(:send_more, %{applying: false}=state) do
    {:noreply, state}
  end

  def handle_info(:send_more, state) do
    timer = Process.send_after(self(), :send_more, 200)
    leader = Cluster.wait_for_election(state.cluster)
    state = apply_commands(state.cluster, leader, state)
    {:noreply, %{state | timer: timer}}
  end

  def apply_commands(cluster, leader, state) do
    (0..5)
    |> Enum.map(fn _ -> random_command(state.generator) end)
    |> Enum.reduce(state, fn command, s -> apply_command(cluster, leader, command, s) end)
  end

  defp apply_command(cluster, leader, command, state) do
    case Raft.write(leader, command, 3_000) do
      {:ok, value} ->
        %{state | writes: [{command, value} | state.writes]}
      {:error, :timeout} ->
        state = %{state | errors: [{command, :timeout} | state.errors]}
        leader = Cluster.wait_for_election(cluster)
        apply_command(cluster, leader, command, state)
      {:error, :election_in_progress} ->
        raise "I don't know what to do here"
      {:error, {:redirect, leader}} ->
        state = %{state | errors: [{command, {:redirect, leader}} | state.errors]}
        apply_command(cluster, leader, command, state)
    end
    catch
      :exit, _ ->
        state
  end

  defp random_command(generator) do
    generator
    |> Enum.take(100)
    |> Enum.random
  end
end
