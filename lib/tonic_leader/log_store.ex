defmodule TonicLeader.LogStore do
  @typep path  :: String.t
  @typep log   :: Log.t
  @typep db    :: term()
  @typep index :: String.t
  @typep key   :: String.t
  @typep value :: String.t

  @callback open(path()) :: {:ok, db()} | {:error, any()}

  @callback store_logs(db(), log()) :: :ok | {:error, any()}

  @callback close(db()) :: :ok | {:error, any()}

  @callback get_log(db(), index()) :: {:ok, log()} | {:error, any()}

  @callback get(db(), key()) :: {:ok, value()} | {:error, any()}

  @callback set(db(), key(), value()) :: :ok | {:error, any()}

  @callback destroy(db()) :: :ok | {:error, any()}

  @callback last_index(db()) :: {:ok, index()} | {:error, any()}

  @current_term "CurrentTerm"

  @doc """
  Opens a new or existing database at the given path.
  """
  def open(path) do
    adapter().open(path)
  end

  @doc """
  Closes the connection to the database
  """
  def close(db) do
    adapter().close(db)
  end

  @doc """
  Gets the current term
  """
  def get_current_term(db) do
    adapter().get(db, @current_term)
  end

  @doc """
  Retrieves the last index thats been saved to stable storage.
  If the database is empty then 0 is returned.
  """
  def last_index(db) do
    adapter().last_index(db)
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
  Gets a log at a specific index.
  """
  def get_log(db, index) do
    adapter().get_log(db, index)
  end

  @doc """
  Store logs in the log store.
  """
  def store_logs(db, entries) do
    adapter().store_logs(db, entries)
  end

  @doc """
  Gets a value from the k/v store.
  """
  def get(db, key) do
    case adapter().get(db, key) do
      {:ok, value} ->
        {:ok, value}
      {:error, :not_found} ->
        {:ok, nil}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Sets a value in the key value store.
  """
  def set(db, key, value) do
    adapter().set(db, key, value)
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
  def has_data?(log_store) do
    last_index(log_store) > 0
  end

  defp adapter, do: Application.get_env(:tonic_leader, :log_store, TonicLeader.LogStore.RocksDB)
end
