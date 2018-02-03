defmodule PropCheck.Fuzzy.ServerCrashes do
  use ExUnit.Case, async: false

  setup do
    Application.ensure_all_started(:tonic_raft)

    :tonic_raft
    |> Application.app_dir
    |> File.cd!(fn ->
      File.ls!()
      |> Enum.filter(fn file -> file =~ ~r/.tonic$/ end)
      |> Enum.map(&Path.relative_to_cwd/1)
      |> Enum.map(&File.rm_rf!/1)
    end)

    on_exit fn ->
      Application.stop(:tonic_raft)
    end

    :ok
  end

  test "crash servers and supervisors" do
    alias TonicRaft.Config

    _a = TonicRaft.start_node(:a, %Config{})
    _b = TonicRaft.start_node(:b, %Config{})
    _c = TonicRaft.start_node(:c, %Config{})

    assert {:ok, _} = TonicRaft.set_configuration(:a, [:a, :b, :c])
    assert {:ok, "set key val"} = TonicRaft.write(:a, "set key val")
    assert :ok = TonicRaft.stop_node(:a)

    case TonicRaft.write(:b, "set key val") do
      {:ok, "set key val"} ->
        assert true
      {:error, {:redirect, leader}} ->
        assert true
        # assert {:ok, "set key val"} = TonicRaft.write(leader, "set key val")
      {:error, :election_in_progress} ->
        assert true
    end

    TonicRaft.stop_node(:b)
  end
end
