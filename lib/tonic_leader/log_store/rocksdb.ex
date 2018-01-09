defmodule TonicLeader.LogStore.RocksDB do
  @behaviour TonicLeader.LogStore

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
  def store_logs(%{logs: db}, entries) do
    with {:ok, batch} <- :rocksdb.batch(),
         encoded      <- encode_entries(entries),
         writes       <- add_entries_to_batch(encoded, batch) do
      :rocksdb.write_batch(db, writes, [])
    end
  end

  @impl true
  def last_index(%{logs: db}) do
    {:ok, itr} = :rocksdb.iterator(db, [])

    case :rocksdb.iterator_move(itr, :last) do
      {:ok, index, _value} ->
        :rocksdb.iterator_close(itr)
        decode_index(index)
      {:error, :invalid_iterator} ->
        :rocksdb.iterator_close(itr)
        0
    end
  end

  @impl true
  def get_log(%{logs: db}, index) do
    case :rocksdb.get(db, encode_index(index), []) do
      {:ok, value} -> {:ok, decode_entry(value)}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  def write_metadata(%{conf: db}, meta) do
    case :rocksdb.put(db, "metadata", encode_entry(meta), []) do
      :ok -> :ok
      error -> {:error, error}
    end
  end

  def get_metadata(%{conf: db}) do
    case :rocksdb.get(db, @metadata, []) do
      {:ok, value} -> {:ok, decode_entry(value)}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  @impl true
  def get(%{conf: db}, key) do
    case :rocksdb.get(db, key, []) do
      {:ok, value} -> {:ok, decode(value)}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  @impl true
  def set(%{conf: db}, key, value) when is_binary(key) do
    case :rocksdb.put(db, key, encode(value), []) do
      :ok -> :ok
      error -> {:error, error}
    end
  end

  @impl true
  def destroy(%{path: path}) do
    path |> db_logs |> File.rm_rf
    path |> db_conf |> File.rm_rf
  end

  # TODO: decode and encode need to be protocols and removed from this module
  defp decode(value) do
    :binary.decode_unsigned(value)
  end

  defp encode(value) do
    to_string(value)
  end

  defp encode_entries(entries) do
    Enum.map(entries, &encode_entry/1)
  end

  defp encode_index(index) do
    :binary.encode_unsigned(index)
  end

  defp encode_entry(entry) do
    {:binary.encode_unsigned(entry.index), pack(entry)}
  end

  defp pack(entry) do
    entry
    |> Jason.encode!
    |> Msgpax.pack!(iodata: false)
  end

  defp unpack!(entry) do
    entry
    |> Msgpax.unpack!
    |> Jason.decode!([keys: :atoms])
  end

  defp decode_entry(entry) do
    unpack!(entry)
  end

  defp decode_index(index) do
    :binary.decode_unsigned(index)
  end

  defp add_entries_to_batch(encoded, batch) do
    Enum.reduce(encoded, batch, fn ({key, value}, batch) ->
      :ok = :rocksdb.batch_put(batch, key, value)
      batch
    end)
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
