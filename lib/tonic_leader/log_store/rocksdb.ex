defmodule TonicLeader.LogStore.RocksDB do
  @behaviour TonicLeader.LogStore
  # @spec open(path()) :: {:ok, db()} | {:error, :failed_to_open_database}
  @db_options [
    create_if_missing: true
  ]

  @impl true
  def open(path) do
    path = to_charlist(path)
    case :rocksdb.open(path, @db_options) do
      {:ok, db}   -> {:ok, db}
      {:error, _} -> {:error, :failed_to_open_database}
    end
  end

  @impl true
  def close(db) do
    :rocksdb.close(db)
  end

  @impl true
  def store_logs(db, entries) do
    # start transaction 
    # encode index as the key
    # encode value as message pack
    # put the index and the value into rocks
    # commit the transaction
    with {:ok, batch} <- :rocksdb.batch(),
         encoded      <- encode_entries(entries),
         writes       <- add_entries_to_batch(encoded, batch) do
      :rocksdb.write_batch(db, writes, [])
    end
  end

  def last_index(db) do
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

  def get(db, index) do
    case :rocksdb.get(db, encode_index(index), []) do
      {:ok, value} -> {:ok, decode_entry(value)}
      :not_found   -> {:error, :not_found}
      error        -> {:error, error}
    end
  end

  defp encode_entries(entries) do
    Enum.map(entries, &encode_entry/1)
  end

  defp encode_index(index) do
    :binary.encode_unsigned(index)
  end

  defp encode_entry(entry) do
    {:binary.encode_unsigned(entry.index), Msgpax.pack!(entry, iodata: false)}
  end

  def decode_entry(entry) do
    Msgpax.unpack!(entry)
  end

  defp decode_index(index) do
    IO.inspect(index, label: "Index in binary")
    :binary.decode_unsigned(index)
  end

  defp add_entries_to_batch(encoded, batch) do
    Enum.reduce(encoded, batch, fn ({key, value}, batch) ->
      :ok = :rocksdb.batch_put(batch, key, value)
      batch
    end)
  end
end
