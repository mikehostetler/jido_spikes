defmodule Kura.Work.Entry do
  @moduledoc false
  use Ash.Resource, domain: Kura.Work, data_layer: AshSqlite.DataLayer

  sqlite do
    table "cell_entries"
    repo Kura.Repo
  end

  attributes do
    uuid_primary_key :id
    attribute :cell_id, :string, allow_nil?: false
    attribute :channel, :string, allow_nil?: false
    attribute :input, :string, allow_nil?: false
    attribute :status, :string, allow_nil?: false
    attribute :output, :string
    attribute :trace, :map
    attribute :kind, :string
    attribute :scope_id, :uuid
    attribute :payload, :map
    create_timestamp :inserted_at
  end

  actions do
    defaults [:read]

    create :record do
      accept [:cell_id, :channel, :input, :status, :output]
    end

    create :enqueue do
      accept [:cell_id, :channel, :input, :status, :kind, :scope_id, :payload]
      argument :id, :uuid, allow_nil?: false
      change set_attribute(:id, arg(:id))
    end

    update :finish do
      accept [:status, :output, :trace]
    end
  end
end
