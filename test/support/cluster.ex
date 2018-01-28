defmodule TonicRaft.Support.Cluster do
  alias TonicRaft.Support.StackFSM
  alias TonicRaft.{Config}

  def start(node_count, fsm \\ StackFSM) do
    names =
      (0..node_count)
      |> Enum.map(& :"s#{&1}")

    names
    |> Enum.map(& start_node(&1, %Config{state_machine: fsm}))

    [first | _] = names

    {:ok, _configuration} = TonicRaft.set_configuration(first, names)

    %{servers: names, errors: [], writes: []}
  end

  def wait_for_election(%{servers: servers}) do
    servers
    |> Enum.map(&TonicRaft.status/1)
    |> Enum.find(& &1.current_state == :leader)
    |> case do
      nil ->
        :timer.sleep(200)
        wait_for_election(%{servers: servers})
      leader ->
        leader.name
    end
  end

  def wait_for_replication(server, index) do
    case TonicRaft.status(server) do
      %{last_index: ^index} ->
        true

      _ ->
        :timer.sleep(100)
        wait_for_replication(server, index)
    end
  end

  def start_node(name, config) do
    {:ok, node} = TonicRaft.start_node(name, config)
    node
  end

  def apply_commands(cluster, leader, commands, count \\ 5) do
    (0..count)
    |> Enum.map(fn _ -> random_command(commands) end)
    |> Enum.reduce(cluster, fn command, c -> apply_command(c, leader, command) end)
  end

  defp apply_command(cluster, leader, command) do
    case TonicRaft.write(leader, command, 3_000) do
      {:ok, value} ->
        %{cluster | writes: [{command, value} | cluster.writes]}
      {:error, :timeout} ->
        cluster = %{cluster | errors: [{command, :timeout} | cluster.errors]}
        leader = wait_for_election(cluster)
        apply_command(cluster, leader, command)
      {:error, :not_leader} ->
        cluster = %{cluster | errors: [{command, :not_leader} | cluster.errors]}
        leader = wait_for_election(cluster)
        apply_command(cluster, leader, command)
    end
  end

  def report(%{writes: writes, errors: errors}) do
    write_count = Enum.count(writes)
    error_count = Enum.count(errors)
    """
    Test Results:

    Total commands run: #{write_count + error_count}
    Writes: #{write_count}
    Errors: #{error_count}
    """
  end

  defp random_command(generator) do
    generator
    |> Enum.take(100)
    |> Enum.random
  end
end
