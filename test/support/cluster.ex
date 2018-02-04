defmodule Raft.Support.Cluster do
  alias Raft.{
    Config,
    LogStore,
    StateMachine.Stack,
  }

  def start(node_count, fsm \\ Stack) do
    names =
      (0..node_count)
      |> Enum.map(& :"s#{&1}")

    names
    |> Enum.map(& start_node(&1, %Config{state_machine: fsm}))

    [first | _] = names

    {:ok, _configuration} = Raft.set_configuration(first, names)

    %{servers: names, errors: [], writes: []}
  end

  def stop(%{servers: servers}) do
    servers
    |> Enum.map(&Raft.stop_node/1)
  end

  def random_shutdown(%{servers: servers}=cluster) do
    server = Enum.random(servers)
    IO.puts "Shutting down #{server}"
    Raft.stop_node(server)
    {server, cluster}
  end

  def restart(cluster, server) do
    start_node(server, %Config{state_machine: Stack})
    cluster
  end

  def wait_for_election(%{servers: servers}) do
    servers
    |> Enum.map(&Raft.status/1)
    |> Enum.filter(fn {resp, _} -> resp == :ok end)
    |> Enum.map(fn {:ok, status} -> status end)
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
    case Raft.status(server) do
      %{last_index: ^index} ->
        true

      _ ->
        :timer.sleep(100)
        wait_for_replication(server, index)
    end
  end

  def start_node(name, config) do
    {:ok, node} = Raft.start_node(name, config)
    node
  end

  def all_fsms_match(%{servers: _servers}, _commands) do
    true
  end

  def all_logs_match(%{servers: servers}, commands) do
    dbs =
      servers
      |> Enum.map(fn s -> {s, Config.db_path(s, %Config{})} end)
      |> Enum.map(fn {s, path} ->
        {:ok, db} = LogStore.open(path)
        {s, db}
      end)


    data = Enum.map dbs, fn {s, db} ->
      data = LogStore.dump_data(db)
      {s, data}
    end

    verify_terms(data) && verify_logs(data, commands)
  end

  defp verify_terms(data) do
    terms = Enum.uniq_by(data, fn {_, d} -> d.term end)
    cond do
      Enum.count(terms) != 1 ->
        raise "Terms don't match for: #{inspect terms}"
      true ->
        true
    end
  end

  defp verify_logs(data, commands) do
    cond do
      (missing=missing_writes(data, commands)) == [] ->
        raise "Commands are missing from logs: #{inspect missing}"

      true ->
        true
    end
  end

  def missing_writes(data, commands) do
    data
    |> Enum.map(& missing_writes_on_server(&1, commands))
    |> Enum.filter(fn {_, ms} -> Enum.count(ms) > 0 end)
  end

  defp missing_writes_on_server({server, %{logs: logs}}, commands) do
    logs = Enum.reject(logs, & &1.type == :noop || &1.type == :config)
    missing = compare_logs(logs, commands, [])
    {server, missing}
  end

  defp compare_logs([], [], missing) do
    missing
  end
  defp compare_logs(logs, [], _missing) when length(logs) > 0 do
    IO.inspect(logs, label: "Logs we don't understand")
    raise "Somehow we have more logs then commands wtf."
  end
  defp compare_logs([], commands, missing) when length(commands) > 0 do
    missing ++ commands
  end
  defp compare_logs([log | logs], [command | commands], missing) do
    cond do
      log.data != command ->
        compare_logs(logs, commands, missing ++ [command])
      true ->
        compare_logs(logs, commands, missing)
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
end
