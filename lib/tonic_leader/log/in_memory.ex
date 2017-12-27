defmodule TonicLeader.Log.InMemory do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def handle_call({:get, key}, _from, data) do
    {:reply, {:ok, get_in(data, [key])}, data}
  end

  def handle_call({:put, key, value}, _from, data) do
    {:reply, {:ok, value}, put_in(data, [key], value)}
  end
end
