defmodule TonicLeader.Configuration do
  @derive Jason.Encoder
  defstruct [state: :none, old_servers: [], new_servers: [], index: 0, latest: %{}]

  @type peer :: atom() | {atom(), atom()}
  @type config_state :: :none
                      | :stable
                      | :staging
                      | :transitional

  @type t :: %__MODULE__{
    state: config_state(),
    old_servers: list(),
    new_servers: list(),
  }

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

    def to_server(server), do: server
  end

  alias __MODULE__
  alias TonicLeader.Log.Entry

  @doc """
  Does the server have a vote.
  """
  @spec has_vote?(Configuration.t) :: boolean()

  def has_vote?(%{state: :none}), do: false

  @doc """
  Is the peer a member of the configuration.
  """
  @spec member?(Configuration.t, peer()) :: boolean()

  def member?(_configuration, _peer) do
    false
  end

  @doc """
  Reconfigures the configuration with new servers. If the configuration state is
  `:none` then it moves directly into a stable configuration. Otherwise it
  starts to transition to a new configuration.
  """
  @spec reconfig(Configuration.t, list()) :: Configuration.t

  def reconfig(%{state: :none}=config, new_servers) do
    %{config | state: :stable, old_servers: new_servers}
  end

  def reconfig(%{state: :stable}=config, new_servers) do
    %{config | state: :transitional, new_servers: new_servers}
  end

  @doc """
  Gets a list of followers
  """
  @spec followers(Config.t, peer()) :: [Server.t]

  def followers(%{state: :stable, old_servers: servers}, peer) do
    Enum.reject(servers, & &1 == peer)
  end

  @doc """
  Builds a new voter server server struct.
  """
  def voter(name, address) do
    %Server{name: name, address: address, suffrage: :voter}
  end

  def quorum(%{state: :stable, old_servers: servers}) do
    count =
      servers
      |> Enum.count

    div(count, 2)+1
  end

  @doc """
  Determines if we have a majority based on the current configuration.
  """
  def majority?(configuration, votes) do
    Enum.count(votes) >= quorum(configuration)
  end

  @doc """
  Gets the maximum index for which we have a quorum.
  """
  @spec quorum_max(Configuration.t, map()) :: non_neg_integer()

  def quorum_max(configuration, indexes) do
    values =
      indexes
      |> Enum.map(fn {_, v} -> v end)
      |> Enum.sort(&>=/2)

    {value, _votes} =
      values
      |> Enum.map(fn v -> {v, Enum.count(values, & &1 >= v)} end)
      |> Enum.find(fn {_, votes} -> votes >= quorum(configuration) end)

    value
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
    |> Map.put(:old_servers, Enum.map(configuration.old_servers, &Server.to_struct/1))
  end

  def restore(logs) do
    logs
    |> Enum.filter(& Entry.type(&1) == :config_change)
    |> Enum.reduce(%Configuration{}, &rebuild_configuration/2)
    |> to_struct
  end

  def rebuild_configuration(log, configuration) do
    configuration
    |> Map.put(:old_servers, log.data.old_servers)
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
    %Configuration{config | old_servers: servers}
  end

  def next(:promote, config, change) do
    servers = Enum.map(config.servers, maybe_promote_server(change.name))
    %Configuration{config | old_servers: servers}
  end

  def next(:remove_server, config, change) do
    new_servers = Enum.reject(config.servers, & change.name == &1.name)
    %Configuration{config | old_servers: new_servers}
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
