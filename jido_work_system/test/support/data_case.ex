defmodule JidoWorkSystem.DataCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      alias JidoWorkSystem.Model
      alias JidoWorkSystem.Simulation
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(JidoWorkSystem.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(JidoWorkSystem.Repo, {:shared, self()})
    :ok
  end
end
