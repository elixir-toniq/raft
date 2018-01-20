defmodule TonicRaft.Config do
  defstruct [
    state_machine: :none,
    name: :none,
    min_election_timeout: 150,
    max_election_timeout: 300,
    heartbeat_timeout: 200,
    data_dir: "",
  ]

  @type t :: %__MODULE__{
    state_machine: :none,
    min_election_timeout: non_neg_integer(),
    max_election_timeout: non_neg_integer(),
    heartbeat_timeout: non_neg_integer(),
    data_dir: String.t,
  }

  def new(opts) do
    valid_opts =
      default_opts()
      |> Keyword.merge(opts)
      |> validate!

    struct(__MODULE__, valid_opts)
  end

  def db_path(name, config), do: config |> data_dir |> Path.join("#{name}")

  def data_dir(%{data_dir: ""}), do: :tonic_raft
                                 |> Application.app_dir()
                                 # |> Path.join("data")

  def data_dir(%{data_dir: data_dir}), do: data_dir

  @doc """
  Generates a random timeout value between the min_election_timeout and
  max_election_timeout.
  """
  @spec election_timeout(t) :: pos_integer()

  def election_timeout(%{min_election_timeout: min, max_election_timeout: max}) do
    case min < max do
      true -> :rand.uniform(max-min)+min
      _    -> throw :min_equals_max
    end
  end

  defp validate!(opts) do
    min = Keyword.get(opts, :min_election_timeout)
    max = Keyword.get(opts, :max_election_timeout)

    if min < max do
      opts
    else
      throw :min_equals_max
    end
  end

  defp default_opts(), do: [
      members: [],
      min_election_timeout: 150,
      max_election_timeout: 300,
      heartbeat_timeout: 200,
    ]
end
