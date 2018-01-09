defmodule TonicLeader.Log.Entry do
  alias __MODULE__

  @derive Jason.Encoder
  defstruct [:index, :term, :type, :data]

  @type index :: pos_integer()
  @type type  :: :command
               | :leader_elected
               | :add_follower
               | :config
               # TODO Implement these
               # | :remove_follower
               # | :configuration_change
  @type data  :: pid()

  @type t :: %__MODULE__{
    index: index(),
    term: pos_integer(),
    type: type(),
    data: data(),
  }

  @log_types [
    command: 0,
    leader_elected: 1,
    add_follower: 2,
    config: 3,
    # TODO Implement these
    # | :remove_follower
    # | :configuration_change
  ]


  @spec add_member(index(), pos_integer(), pid()) :: Entry.t
  def add_member(index, term, member) do
    %__MODULE__{index: index, term: term, type: :add_member, data: member}
  end

  def configuration?(entry), do: type(entry) == :config

  @doc """
  The type of log.
  """
  def type(%{type: type}) do
    {name, _} = Enum.find(@log_types, fn {_, i} -> type == i end)
    name
  end

  def type(name), do: Keyword.get(@log_types, name)
end
