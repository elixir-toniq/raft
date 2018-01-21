defmodule TonicRaft.Log do
  use GenServer
  require Logger

  alias TonicRaft.{
    Config,
    Log.Entry,
    LogStore,
  }

  @type index :: non_neg_integer()
  @type log_term :: non_neg_integer()
  @type candidate :: atom() | :none
  @type metadata :: %{
    term: non_neg_integer(),
    voted_for: atom() | nil,
  }

  def start_link([name, config]) do
    GenServer.start_link(__MODULE__, {name, config}, name: log_name(name))
  end

  @doc """
  Appends new entries to the log and returns the latest index.
  """
  @spec append(atom(), [Entry.t]) :: {:ok, index()} | {:error, term()}

  def append(name, entries) when is_list(entries) do
    call(name, {:append, entries})
  end

  @doc """
  Gets the entry at the given index.
  """
  @spec get_entry(atom(), index()) :: {:ok, Entry.t} | {:error, :not_found}

  def get_entry(name, index) do
    call(name, {:get_entry, index})
  end

  @doc """
  Gets the current metadata for the server.
  """
  @spec get_metadata(atom()) :: metadata()

  def get_metadata(name) do
    call(name, :get_metadata)
  end

  @doc """
  Sets metadata.
  """
  @spec set_metadata(atom(), candidate(), log_term()) :: {:ok, metadata()}

  def set_metadata(name, candidate, term) do
    call(name, {:set_metadata, candidate, term})
  end

  def get_configuration(name), do: call(name, :get_configuration)

  def last_index(name), do: call(name, :last_index)

  def init({name, opts}) do
    Logger.info("#{log_name(name)}: Restoring old state", metadata: name)
    {:ok, log_store} = LogStore.open(Config.db_path(name, opts))

    configuration       = LogStore.get_config(log_store)
    metadata            = LogStore.get_metadata(log_store)
    last_index          = LogStore.last_index(log_store)
    # start_index         = 0 # TODO: This should be the index of the last snapshot if there is one
    # logs                = LogStore.slice(log_store, start_index..last_index)
    # configuration       = Configuration.restore(logs)

    state = %{
      log_store: log_store,
      configuration: configuration,
      metadata: metadata,
      last_index: last_index,
    }
    {:ok, state}
  end

  def handle_call({:append, entries}, _from, state) do
    state = Enum.reduce(entries, state, fn entry, state ->
      entry = %{entry | index: state.last_index+1}
      :ok = LogStore.store_logs(state.log_store, [entry])
      state = apply_entry(state, entry)
      %{state | last_index: entry.index}
    end)

    {:reply, {:ok, state.last_index}, state}
  end

  def handle_call({:get_entry, index}, _from, state) do
    result = LogStore.get_log(state.log_store, index)
    {:reply, result, state}
  end

  def handle_call(:get_metadata, _from, %{metadata: meta}=state) do
    {:reply, meta, state}
  end

  def handle_call({:set_metadata, cand, term}, _from, state) do
    metadata = %{voted_for: cand, term: term}
    :ok = LogStore.write_metadata(state.log_store, metadata)
    {:reply, :ok, %{state | metadata: metadata}}
  end

  def handle_call(:get_configuration, _from, %{configuration: config}=state) do
    {:reply, config, state}
  end

  def handle_call(:last_index, _from, state) do
    {:reply, state.last_index, state}
  end

  defp call(name, msg), do: GenServer.call(log_name(name), msg)

  defp log_name(name), do: :"#{name}_log"

  defp apply_entry(state, %{type: 3, data: data}=entry) do
    %{state | configuration: data}
  end

  # alias TonicRaft.Log.Entry

  # @typep index :: pos_integer()

  # @type t :: %__MODULE__{
  #   entries: %{required(index()) => Entry.t},
  #   commit_index: index(),
  #   last_applied: index(),
  # }

  # @doc """
  # Initializes a new log.
  # """
  # def new, do: %Log{}

  # @doc """
  # Returns all entries greater then or equal to a given index.
  # """
  # @spec from_index(Log.t, index()) :: [Entry.t]

  # def from_index(%{entries: entries}, index) do
  #   entries
  #   |> Enum.filter(fn {k, _} -> k >= index end)
  #   |> to_list
  # end

  # def to_list(entries) do
  #   Enum.map(entries, fn {_, entry} -> entry end)
  # end

end
