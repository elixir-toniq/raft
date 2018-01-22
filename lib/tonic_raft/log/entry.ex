defmodule TonicRaft.Log.Entry do
  @derive Jason.Encoder
  defstruct [:index, :term, :type, :data]

  @typedoc """
  The index the entry is stored at. Defaults to `:none`. Entries are created
  with a `:none` index and the index is populated when it is appened to the log.
  """
  @type index :: :none
               | non_neg_integer()

  @typedoc """
  The term the entry was stored in.
  """
  @type current_term :: non_neg_integer()

  @typedoc """
  Types of entries.

  `:command` - A command sent from the client.
  `:config` - Configuration changes.
  `:noop` - Written when a leader first comes to power so that we can move the
  commit index forward. Since we can only commit entries from our current term
  based on Raft's safety description in 5.4.2 we do this immediately in order to
  force a commitment based on replication. The noop is only discussed briefly
  in section 8. "Client Interaction".
  """
  @type type :: :command
              | :config
              | :noop

  @typedoc """
  The command or configuration data sent by the client.
  """
  @type data :: :none | term()

  @typedoc """
  The Entry struct.
  """
  @type t :: %__MODULE__{
    index: index(),
    term: current_term(),
    type: type(),
    data: data(),
  }

  @doc """
  Buids a configuration entry.
  """
  def configuration(term, configuration) do
    %__MODULE__{
      index: :none,
      type: :config,
      term: term,
      data: configuration,
    }
  end

  def command(term, cmd) do
    %__MODULE__{
      index: :none,
      type: :command,
      term: term,
      data: cmd,
    }
  end

  def noop(term) do
    %__MODULE__{
      index: :none,
      type: :noop,
      term: term,
      data: :none,
    }
  end
end
