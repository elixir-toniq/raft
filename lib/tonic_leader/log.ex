defmodule TonicLeader.Log do
  def get(key) do
    adapter().get(key)
  end

  def put(key, value) do
    adapter().put(key, value)
  end

  defp adapter(), do: Application.get_env(:tonic_leader, :log_adapter)
end
