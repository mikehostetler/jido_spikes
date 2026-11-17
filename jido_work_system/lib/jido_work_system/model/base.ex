defmodule JidoWorkSystem.Model.Base do
  @moduledoc false

  defmacro __using__(opts) do
    table = Keyword.fetch!(opts, :table)

    quote do
      use Ash.Resource,
        domain: JidoWorkSystem.Work,
        data_layer: AshSqlite.DataLayer

      sqlite do
        table(unquote(table))
        repo(JidoWorkSystem.Repo)
      end

      actions do
        defaults([:read, :destroy, create: :*, update: :*])
      end

      attributes do
        uuid_primary_key(:id)
        timestamps()
      end
    end
  end
end
