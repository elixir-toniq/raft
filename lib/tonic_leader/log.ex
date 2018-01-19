defmodule TonicLeader.Log do
  defstruct [entries: %{}, commit_index: 0, last_applied: 0]

  alias __MODULE__
  alias TonicLeader.Log.Entry

  @typep index :: pos_integer()

  @type t :: %__MODULE__{
    entries: %{required(index()) => Entry.t},
    commit_index: index(),
    last_applied: index(),
  }

  @doc """
  Initializes a new log.
  """
  def new, do: %Log{}

  @doc """
  Returns all entries greater then or equal to a given index.
  """
  @spec from_index(Log.t, index()) :: [Entry.t]

  def from_index(%{entries: entries}, index) do
    entries
    |> Enum.filter(fn {k, _} -> k >= index end)
    |> to_list
  end

  def to_list(entries) do
    Enum.map(entries, fn {_, entry} -> entry end)
  end

  @doc """
  Adds a new configuration log
  """
  def configuration(index, term, configuration) do
    %{
      type: Entry.type(:config),
      term: term,
      index: index,
      data: configuration,
    }
  end
end
