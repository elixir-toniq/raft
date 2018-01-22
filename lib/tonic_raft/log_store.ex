defmodule TonicRaft.LogStore do
  alias TonicRaft.Log.{
    Entry,
    Metadata,
  }

  @typep path  :: String.t
  @typep db    :: term()
  @typep index :: non_neg_integer()
  @typep key :: String.t
  @typep encoded :: String.t
  @type metadata :: Metadata.t

  @callback open(path()) :: {:ok, db()} | {:error, any()}

  @callback store_entry(db(), key(), encoded()) :: :ok | {:error, any()}

  @callback get_entry(db(), key()) :: {:ok, encoded()} | {:error, :not_found}

  @callback last_entry(db()) :: {:ok, encoded()} | {:ok, :empty}

  @callback store_metadata(db(), encoded()) :: :ok | {:error, any()}

  @callback get_metadata(db()) :: {:ok, encoded()} | {:error, :not_found}

  @callback close(db()) :: :ok | {:error, any()}

  @callback destroy(db()) :: :ok | {:error, any()}

  @doc """
  Opens a new or existing database at the given path.
  """
  @spec open(path()) :: db()

  def open(path) do
    adapter().open(path)
  end

  @doc """
  Closes the connection to the database
  """
  @spec close(db()) :: :ok

  def close(db) do
    adapter().close(db)
  end

  @doc """
  Store logs in the log store and returns the last index.
  """
  @spec store_entries(db(), [Entry.t]) :: {:ok, index()}

  def store_entries(db, entries) when is_list(entries) do
    last_index = Enum.reduce entries, nil, fn entry, _ ->
      index = encode_index(entry.index)
      encoded = encode(entry)
      :ok = adapter().store_entry(db, index, encoded)
      index
    end

    {:ok, decode_index(last_index)}
  end


  @doc """
  Gets all metadata from the store.
  """
  @spec get_metadata(db()) :: metadata()

  def get_metadata(db) do
    case adapter().get_metadata(db) do
      {:ok, metadata} ->
        decode(metadata)
      {:error, :not_found} ->
        %Metadata{term: 0, voted_for: :none}
    end
  end

  @doc """
  Stores the metadata.
  """
  @spec store_metadata(db(), metadata()) :: :ok

  def store_metadata(db, meta) do
    adapter().store_metadata(db, encode(meta))
  end

  @doc """
  Gets a log at a specific index.
  """
  @spec get_entry(db(), index()) :: {:ok, Entry.t} | {:error, :not_found}

  def get_entry(db, index) do
    case adapter().get_entry(db, encode_index(index)) do
      {:ok, value} ->
        {:ok, decode(value)}
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Retrieves the last entry from the log. Returns `:empty` if the log is empty.
  """
  @spec last_entry(db()) :: {:ok, Entry.t} | {:ok, :empty}

  def last_entry(db) do
    case adapter().last_entry(db) do
      {:ok, :empty} ->
        {:ok, :empty}

      {:ok, value} ->
        {:ok, decode(value)}
    end
  end

  @doc """
  Retrieves the last index thats been saved to stable storage.
  If the database is empty then 0 is returned.
  """
  @spec last_index(db()) :: index()

  def last_index(db) do
    case last_entry(db) do
      {:ok, %{index: index}} ->
        index

      {:ok, :empty} ->
        0
    end
  end

  @doc """
  Gets all logs from starting index to end index inclusive.
  """
  def slice(db, range) do
    range
    |> Enum.map(& adapter().get_log(db, &1))
    |> Enum.map(fn {:ok, value} -> value end)
  end

  @doc """
  Used to destroy the data on disk. This is used for testing and development
  and is dangerous to run in production.
  """
  def destroy(db) do
    adapter().destroy(db)
  end

  @doc """
  Determines if anything has been written to the log yet.
  """
  @spec has_data?(db()) :: boolean()

  def has_data?(db) do
    last_index(db) > 0
  end

  defp decode(value) when is_binary(value) do
    :erlang.binary_to_term(value)
  end

  defp encode(value) do
    :erlang.term_to_binary(value)
  end

  defp encode_index(index) when is_integer(index) do
    Integer.to_string(index)
  end

  defp decode_index(index) when is_binary(index) do
    String.to_integer(index)
  end

  defp adapter, do: Application.get_env(:tonic_raft, :log_store, TonicRaft.LogStore.RocksDB)
end
