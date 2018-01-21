defmodule TonicRaft.LogStore.RocksDB do
  @behaviour TonicRaft.LogStore

  @db_logs "logs.tonic"
  @db_conf "conf.tonic"
  @metadata "metadata"

  @db_options [
    create_if_missing: true
  ]

  defstruct [:logs, :conf, :path]

  @impl true
  def open(path) do
    with {:ok, logs} <- open_logs(path),
         {:ok, conf} <- open_conf(path) do

      {:ok, %__MODULE__{logs: logs, conf: conf, path: path}}
    else
      {:error, _} ->
        {:error, :failed_to_open_database}
    end
  end

  @impl true
  def close(%{logs: logs, conf: conf}) do
    :rocksdb.close(logs)
    :rocksdb.close(conf)
  end

  @impl true
  def store_entry(%{logs: db}, index, entry) do
    put(db, index, entry)
  end

  @impl true
  def get_entry(%{logs: db}, index) do
    case get(db, index) do
      {:ok, value} -> {:ok, value}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  @impl true
  def store_metadata(%{conf: db}, meta) do
    case put(db, @metadata, meta) do
      :ok -> :ok
      error -> {:error, error}
    end
  end

  @impl true
  def get_metadata(%{conf: db}) do
    case get(db, @metadata) do
      {:ok, value} -> {:ok, value}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  @impl true
  def last_index(%{logs: db}) do
    {:ok, itr} = :rocksdb.iterator(db, [])

    case :rocksdb.iterator_move(itr, :last) do
      {:ok, index, _value} ->
        :rocksdb.iterator_close(itr)
        index
      {:error, :invalid_iterator} ->
        :rocksdb.iterator_close(itr)
        "0"
    end
  end

  @impl true
  def destroy(%{path: path}) do
    {:ok, _} = path |> db_logs |> File.rm_rf
    {:ok, _} = path |> db_conf |> File.rm_rf

    :ok
  end

  defp put(db, key, value) when is_binary(key) and is_binary(value) do
    :rocksdb.put(db, key, value, [])
  end

  def get(db, key) when is_binary(key) do
    :rocksdb.get(db, key, [])
  end

  defp db_logs(path), do: path <> "_" <> @db_logs
  defp db_conf(path), do: path <> "_" <> @db_conf

  defp open_logs(path) do
    path
    |> db_logs
    |> open_db
  end

  defp open_conf(path) do
    path
    |> db_conf
    |> open_db
  end

  defp open_db(path) do
    path
    |> to_charlist
    |> :rocksdb.open(@db_options)
  end
end
