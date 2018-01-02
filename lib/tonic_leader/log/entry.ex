defmodule TonicLeader.Log.Entry do
  defstruct [:index, :term, :type, :data]

  @type index :: pos_integer()
  @type type  :: :command
               | :leader_elected
               | :add_follower
               | :config_change
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

  @spec add_member(index(), pos_integer(), pid()) :: Entry.t
  def add_member(index, term, member) do
    %__MODULE__{index: index, term: term, type: :add_member, data: member}
  end
end
