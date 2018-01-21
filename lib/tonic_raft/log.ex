defmodule TonicRaft.Log do
  use GenServer
  require Logger

  alias TonicRaft.{
    Config,
    Log.Entry,
    Log.Metadata,
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
  @spec set_metadata(atom(), candidate(), log_term()) :: :ok

  def set_metadata(name, candidate, term) do
    call(name, {:set_metadata, candidate, term})
  end

  def get_configuration(name), do: call(name, :get_configuration)

  def last_index(name), do: call(name, :last_index)

  def init({name, opts}) do
    Logger.info("#{log_name(name)}: Restoring old state", metadata: name)
    {:ok, log_store} = LogStore.open(Config.db_path(name, opts))

    metadata            = LogStore.get_metadata(log_store)
    last_index          = LogStore.last_index(log_store)

    # TODO - This is broken. It needs to rebuild this from logs.
    configuration       = %TonicRaft.Configuration{}

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
      {:ok, last_index} = LogStore.store_entries(state.log_store, [entry])
      state = apply_entry(state, entry)
      %{state | last_index: last_index}
    end)

    {:reply, {:ok, state.last_index}, state}
  end

  def handle_call({:get_entry, index}, _from, state) do
    result = LogStore.get_entry(state.log_store, index)
    {:reply, result, state}
  end

  def handle_call(:get_metadata, _from, %{metadata: meta}=state) do
    {:reply, meta, state}
  end

  def handle_call({:set_metadata, cand, term}, _from, state) do
    metadata = %Metadata{voted_for: cand, term: term}
    :ok = LogStore.store_metadata(state.log_store, metadata)
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

  defp apply_entry(state, %{type: :config, data: data}) do
    %{state | configuration: data}
  end
end
