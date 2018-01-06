defmodule TonicLeader.Configuration do
  @derive Jason.Encoder
  defstruct [servers: [], index: 0, latest: %{}]

  defmodule Server do
    @type t :: %__MODULE__{
      name: atom(),
      address: atom(),
      suffrage: :voter | :staging,
    }

    @derive Jason.Encoder
    defstruct [suffrage: :staging, name: :none, address: nil]

    def to_struct(server), do: %__MODULE__{
      suffrage: String.to_existing_atom(server.suffrage),
      address: String.to_existing_atom(server.address),
      name: String.to_existing_atom(server.name),
    }

    def to_server(server), do: {server.name, server.address}
  end

  alias __MODULE__
  alias TonicLeader.Log.Entry

  @doc """
  Builds a new voter server server struct.
  """
  def voter(name, address) do
    %Server{name: name, address: address, suffrage: :voter}
  end

  def quorum(configuration) do
    count =
      configuration
      |> Map.get(:servers)
      |> Enum.filter(& &1.suffrage == :voter)
      |> Enum.count

    div(count, 2)+1
  end

  def encode(configuration) do
    configuration
    |> Jason.encode!
    |> Msgpax.pack!(iodata: false)
  end

  def decode(configuration) do
    configuration
    |> Msgpax.unpack!
    |> Jason.decode!([keys: :atoms])
  end

  defp to_struct(configuration) do
    configuration
    |> Map.put(:servers, Enum.map(configuration.servers, &Server.to_struct/1))
  end

  def restore(logs) do
    logs
    |> Enum.filter(& Entry.type(&1) == :config_change)
    |> Enum.reduce(%Configuration{}, &rebuild_configuration/2)
    |> to_struct
  end

  def rebuild_configuration(log, configuration) do
    configuration
    |> Map.put(:servers, log.data.servers)
    |> Map.put(:index, log.data.index)
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
