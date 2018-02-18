# Raft

Raft provides users with an api for building consistent (as defined by CAP),
distributed state machines. It does this using the raft leader election and
concensus protocol as described in the [original
paper](https://raft.github.io/raft.pdf). Logs are persisted using rocksdb
but Raft provides a pluggable storage adapter for utilizing other storage
engines.

## Installation

```elixir
def deps do
  [
    {:raft, "~> 0.2.0"},
  ]
end
```

## Example

Lets build a distributed key value store. The first thing that we'll need
is a state machine:

```elixir
defmodule KVStore do
  use Raft.StateMachine

  @initial_state %{}

  def set(name, key, value) do
    Raft.write(name, {:set, key, value})
  end

  def get(name, key) do
    Raft.read(name, {:get, key})
  end

  def init(_name) do
    {:ok, @initial_state} 
  end

  def handle_write({:set, key, value}, state) do
    {{:ok, key, value}, put_in(state, [key], value)}
  end

  def handle_read({:get, key}, state) do
    case get_in(state, [key]) do
      nil ->
        {{:error, :key_not_found}, state}

      value ->
        {{:ok, value}, state}
    end
  end
end
```

Now we can start our peers. Its important to note that each peer must be
given a unique name within the cluster.

```elixir
{:ok, _pid} = Raft.start_peer(KVStore, name: :s1)
{:ok, _pid} = Raft.start_peer(KVStore, name: :s2)
{:ok, _pid} = Raft.start_peer(KVStore, name: :s3)
```

At this point our peers are started but currently they're all in the
"follower" state. In order to get them to communicate we need to define
a cluster configuration for them like so:

```elixir
Raft.set_configuration(:s1, [:s1, :s2, :s3])
```

Once this command runs the peers will start an election and elect
a leader. You can see who the current leader is by running:

```elixir
leader = Raft.leader(:s1)
```

Once we have the leader we can read and write to our state machine:

```elixir
{:ok, :foo, :bar} = KVStore.write(leader, :foo, :bar)
{:ok, :bar} = KVStore.read(leader, :foo)
{:error, :key_not_found} = KVStore.get(leader, :baz)
```

We can now shutdown our leader and ensure that a new leader has been
elected and our state is replicated across all of our peers:

```elixir
Raft.stop(leader)

# wait for election...

new_leader = Raft.leader(:s2)
{:ok, :bar} = KVStore.read(new_leader, :foo)
```

We now have a consistent, replicated key-value store. If you want to read more
about the internals of the project or read up on the raft protocol please check out
the [hex docs](https://hexdocs.pm/raft).

## Caution

This project is not quite ready for production use. If you would like to help
test out the implementation that would be greatly appreciated.

## Contributing

The goal of this project is to provide the elixir community with
a standard way of building consistent systems. Pull requests and issues
are very welcome. If you would like to get involved here's some of the
immediate needs.

* [ ] - Configuration changes
* [ ] - Automatic cluster joining
* [ ] - Snapshotting
* [ ] - Alternative storage engine using lmdb
* [ ] - Jepsen testing

