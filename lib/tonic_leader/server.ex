defmodule TonicLeader.Server do
  use GenStateMachine

  alias TonicLeader.Log

  @default_state %{
    current_term: 0,
    election_timeout: 0,
  }

  def start_link() do
    GenStateMachine.start_link(__MODULE__, {:follower, []})
  end

  def current_state(sm) do
    GenStateMachine.call(sm, :current_state)
  end

  def get(sm, key) do
    GenStateMachine.call(sm, {:get, key})
  end

  def put(sm, key, value) do
    GenStateMachine.call(sm, {:put, key, value})
  end

  def handle_event({:call, from}, :current_state, state, data) do
    {:next_state, state, data, [{:reply, from, state}]}
  end

  def handle_event({:call, from}, {:get, key}, state, data) do
    {:ok, value} = Log.get(key)
    {:keep_state_and_data, [{:reply, from, value}]}
  end

  def handle_event({:call, from}, {:put, key, value}, state, data) do
    {:ok, value} = Log.put(key, value)
    {:keep_state_and_data, [{:reply, from, value}]}
  end

  def handle_event(:cast, :election_timeout, :follower, data) do
    new_data = data
    {:next_state, :candidate, new_data}
  end

  def handle_event(event_type, event, state, data) do
    IO.inspect([event_type, event, state, data])
  end
end

