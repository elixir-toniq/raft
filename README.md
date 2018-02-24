# Raft

Raft provides users with an api for building consistent (as defined by CAP),
distributed state machines. It does this using the raft leader election and
consensus protocol as described in the [original
paper](https://raft.github.io/raft.pdf). Logs are persisted using rocksdb
but Raft provides a pluggable storage adapter for utilizing other storage
engines.

## Installation

```elixir
def deps do
  [
    {:raft, "~> 0.2.1"},
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

  def write(name, key, value) do
    Raft.write(name, {:set, key, value})
  end

  def read(name, key) do
    Raft.read(name, {:get, key})
  end

  def init(_name) do
    @initial_state
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
given a unique name within the cluster. In this example we'll create
three codes with shortnames `a`, `b`, and `c`. The Raft peers on these
nodes are called `peer1`, `peer2`, and `peer3`.,

```elixir
$ iex --sname a -S mix
iex(a@mymachine)> {:ok, _pid} = Raft.start_peer(KVStore, name: :peer1)

$ iex --sname b -S mix
iex(b@mymachine)> {:ok, _pid} = Raft.start_peer(KVStore, name: :peer2)

$ iex --sname c -S mix
iex(c@mymachine)> {:ok, _pid} = Raft.start_peer(KVStore, name: :peer3)
```

At this point our peers are started but currently they're all in the
"follower" state. In order to get them to communicate we need to define
a cluster configuration for them like so. This needs to be done on
only one of the nodes. In our case, we'll run it on node `a`.

```elixir
iex(a@mymachine)> Raft.set_configuration(:peer1,
            ...> [{ :peer1, :a@mymachine },
            ...>  { :peer2, :b@mymachine },
            ...>  { :peer3, :c@mymachine }]
```

Notice that we have to give both the peer name and the node name, even
for the local peer. That's because we store this configuration in the
replicated logs, and so they must make sense from all our nodes.

Once this command runs the peers will start an election and elect
a leader. You can see who the current leader is by running:

```elixir
leader = Raft.leader(:peer1)
```

Once we have the leader we can read and write to our state machine:

```elixir
{:ok, :foo, :bar} = KVStore.write(leader, :foo, :bar)
{:ok, :bar}       = KVStore.read(leader, :foo)
{:error, :key_not_found} = KVStore.read(leader, :baz)
```

We can now shutdown our leader and ensure that a new leader has been
elected and our state is replicated across all of our peers:

```elixir
iex(a@mymachine)> Raft.stop(leader)
```

Try to use the old leader:

```elixir
iex(a@mymachine)> KVStore.read(leader, :foo)
{ :error, { :redirect, { :peer3, :c@mymachine }}}
```

We're told that the leader has changed.

``` elixir
iex(b@mymachine)> new_leader = Raft.leader(:peer2)
# or
new_leader = { :peer3, :c@mymachine }
```

And use it:

``` elixirt
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
