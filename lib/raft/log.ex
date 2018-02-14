defmodule Raft.Log do
  @moduledoc """
  The `Log` module provides an api for all log operations. Since the log process
  is the only process that can access the underlying log store we cache several
  values in the log process state.
  """

  use GenServer
  require Logger

  alias Raft.{
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
  Gets the current term.
  """
  @spec get_term(atom()) :: log_term()

  def get_term(name) do
    %{term: term} = get_metadata(name)
    term
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

  @doc """
  Gets the current configuration.
  """
  def get_configuration(name), do: call(name, :get_configuration)

  @doc """
  Deletes all logs in the range inclusivesly
  """
  def delete_range(name, a, b) when a <= b do
    call(name, {:delete_range, a, b})
  end
  def delete_range(_name, _, _) do
    :ok
  end

  @doc """
  Returns the last entry in the log. If there are no entries then it returns an
  `:error`.
  """
  @spec last_entry(atom()) :: {:ok, Entry.t} | :empty

  def last_entry(name) do
    call(name, :last_entry)
  end

  @doc """
  Returns the index of the last entry in the log.
  """
  @spec last_index(atom()) :: non_neg_integer()

  def last_index(name) do
    case last_entry(name) do
      {:ok, %{index: index}} ->
        index

      :empty ->
        0
    end
  end

  @doc """
  Returns the term of the last entry in the log. If the log is empty returns
  0.
  """
  @spec last_term(atom()) :: non_neg_integer()

  def last_term(name) do
    case last_entry(name) do
      {:ok, %{term: term}} ->
        term

      :empty ->
        0
    end
  end

  def init({name, opts}) do
    Logger.info("#{log_name(name)}: Restoring old state", metadata: name)
    {:ok, log_store} = case name do
      {me, _} ->
        LogStore.open(Config.db_path(me, opts))

      ^name ->
        LogStore.open(Config.db_path(name, opts))
    end

    metadata = LogStore.get_metadata(log_store)
    last_index = LogStore.last_index(log_store)

    state = %{
      name: name,
      log_store: log_store,
      metadata: metadata,
      last_index: last_index,
      configuration: nil,
    }
    state = init_log(state)
    {:ok, state}
  end

  def handle_call({:append, entries}, _from, state) do
    state = append_entries(state, entries)

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

  def handle_call({:delete_range, a, b}, _from, state) do
    :ok = LogStore.delete_range(state.log_store, a..b)
    last_index = LogStore.last_index(state.log_store)
    state = %{state | last_index: last_index}
    {:reply, :ok, state}
  end

  def handle_call(:last_entry, _from, state) do
    case LogStore.last_entry(state.log_store) do
      {:ok, :empty} ->
        {:reply, :empty, state}

      {:ok, entry} ->
        {:reply, {:ok, entry}, state}
    end
  end

  defp call(name, msg), do: GenServer.call(log_name(name), msg)

  defp log_name({name, _}), do: log_name(name)
  defp log_name(name), do: :"#{name}_log"

  defp apply_entry(state, %{type: :config, data: data}) do
    %{state | configuration: data}
  end

  defp apply_entry(state, _) do
    state
  end

  defp init_log(state) do
    case LogStore.has_data?(state.log_store) do
      true ->
        Logger.debug("#{log_name(state.name)} has data")
        restore_configuration(state)
      false ->
        configuration = %Raft.Configuration{}
        entry = Entry.configuration(0, configuration)
        entry = %{entry | index: 0}
        {:ok, last_index} = LogStore.store_entries(state.log_store, [entry])
        %{state | configuration: configuration, last_index: last_index}
    end
  end

  defp append_entries(state, entries) do
    Enum.reduce entries, state, fn entry, state ->
      entry = add_index(entry, state.last_index)
      {:ok, last_index} = LogStore.store_entries(state.log_store, [entry])
      Logger.debug("#{log_name(state.name)}: Stored up to #{last_index}")
      state = apply_entry(state, entry)
      %{state | last_index: entry.index}
    end
  end

  defp add_index(%{index: :none}=entry, index) do
    %{entry | index: index+1}
  end
  defp add_index(entry, _), do: entry

  defp restore_configuration(%{log_store: log_store, last_index: index}=state) do
    log_store
    |> LogStore.slice(0..index)
    |> Enum.filter(&Entry.configuration?/1)
    |> Enum.reduce(state, fn entry, old_state -> apply_entry(old_state, entry) end)
  end
end
