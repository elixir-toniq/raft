defmodule TonicRaft.Fuzzy.LeaderElectionTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  defmodule Foo do
    def status(msg) do
      IO.puts msg
    end
  end

  defmodule Model do
    def init, do: :starting

    def command(:starting) do
      {:call, Foo, :status, ["The model is starting"]}
    end

    def command(:running) do
      {:call, Foo, :status, ["the model is running"]}
    end

    def next_state(:starting, _, {:call, Foo, :status, _}) do
      :running
    end

    def next_state(:running, _, {:call, Foo, :status, _}) do
      :running
    end
  end

  # defmodule Model do
  #   def next(state, cmd, actual_result) do
  #     state
  #   end

  #   def check(state, cmd, actual_result) do
  #     true
  #   end
  # end

  defmodule DuckDuckGoose do
    def init, do: :goose

    def command(:goose), do: {constant(:goose), :duck}
    def command(:duck), do: {constant(:duck), :duck}
  end

  property "duck duck goose" do
    next = fn
      :duck -> {constant(:duck), :duck}
      :goose -> {constant(:goose), :duck}
    end
    check all commands <- unfold(:goose, next, min_length: 1) do
      # result = run(Model, commands)
      # assert result
      goose = Enum.drop_while(commands, & &1 == :duck)
      assert goose == [:goose]
    end
  end

  def run(model, commands) when is_list(commands) do
    Enum.reduce(commands, {model.init(), true}, &run_command(model, &1, &2))
  end

  def run_command(model, {:call, mod, fun, args}=cmd, {state, result}) do
    {:ok, actual_result} = apply(mod, fun, args)
    {:ok, model_state} = apply(model, :next, [state, cmd, actual_result])
    {:ok, new_result} = apply(model, :check, [state, cmd, actual_result])
    new_result
  end

  def commands(Model) do
    unfold(Model.init, fn val -> {constant(val), Model.command(val)} end, min_length: 1)
  end

  property "leaders are elected" do
    check all commands <- commands(Model) do
      assert Enum.count(commands) >= 1
    end
  end
end
