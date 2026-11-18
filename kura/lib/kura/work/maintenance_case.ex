defmodule Kura.Work.MaintenanceCase do
  @moduledoc false
  use Ash.Resource, domain: Kura.Work, data_layer: AshSqlite.DataLayer

  sqlite do
    table "maintenance_cases"
    repo Kura.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :state, :map, allow_nil?: false
    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :open do
      accept [:state]
    end

    update :advance do
      accept [:state]
    end
  end
end
