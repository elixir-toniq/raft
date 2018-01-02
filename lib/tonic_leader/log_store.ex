defmodule TonicLeader.LogStore do
  @typep path :: String.t
  @typep log  :: Log.t
  @typep db   :: term()

  @callback open(path()) :: {:ok, db()} | {:error, any()}

  @callback store_logs(db(), log()) :: :ok | {:error, any()}

  @callback close(db()) :: :ok | {:error, any()}

  def open(path) do
    adapter().open(path)
  end

  def store_logs(db, entries) do
    adapter().store_logs(db, entries)
  end

  @doc """
  Retrieves the last index thats been saved to stable storage.
  If the database is empty then 0 is returned.
  """
  def last_index(db) do
    adapter().last_index(db)
  end

  def get(db, index) do
    adapter().get(db, index)
  end

  defp adapter, do: Application.get_env(:tonic_leader, :log_store, TonicLeader.LogStore.RocksDB)
end
