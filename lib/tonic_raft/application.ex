defmodule TonicRaft.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      TonicRaft.Server.Supervisor,
    ]

    opts = [strategy: :one_for_one, name: TonicRaft.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
