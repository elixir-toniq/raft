defmodule TonicLeader.Configuration do
  defstruct [servers: [], index: 0]

  defmodule Server do
    defstruct [suffrage: :staging, name: :none, address: nil]
  end

  alias __MODULE__

  def encode(configuration) do
    Msgpax.pack!(configuration, iodata: false)
  end

  def decode(configuration) do
    Msgpax.pack!(configuration, iodata: false)
  end

  def next(%{prev_index: prev_i}, %{index: i}) when prev_i != i do
    {:error, :configuration_changed}
  end
  def next(config, change) do
    next(change.command, config, change)
  end

  def next(:add_voter, config, change) do
    new_server = %Server{
      suffrage: :staging,
      name: change.name,
      address: change.address,
    }
    server_i = Enum.find_index(config.servers, & &1.name == change.name)
    servers = List.update_at(config.servers, server_i, maybe_add_server(new_server))
    %Configuration{config | servers: servers}
  end

  def next(:promote, config, change) do
    servers = Enum.map(config.servers, maybe_promote_server(change.name))
    %Configuration{config | servers: servers}
  end

  def next(:remove_server, config, change) do
    new_servers = Enum.reject(config.servers, & change.name == &1.name)
    %Configuration{config | servers: new_servers}
  end

  defp maybe_promote_server(name) do
    fn server ->
      if server.name == name && server.suffrage == :staging do
        %Server{server | suffrage: :voter}
      else
        server
      end
    end
  end

  defp maybe_add_server(new_server) do
    fn server ->
      if server.suffrage == :voter do
        %Server{server | address: new_server.address}
      else
        new_server
      end
    end
  end
end
