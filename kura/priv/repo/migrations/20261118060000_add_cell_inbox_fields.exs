defmodule Kura.Repo.Migrations.AddCellInboxFields do
  use Ecto.Migration

  def change do
    alter table(:cell_entries) do
      add :kind, :text
      add :scope_id, :uuid
      add :payload, :map
    end

    create index(:cell_entries, [:cell_id, :status, :inserted_at])
    create index(:cell_entries, [:cell_id, :scope_id, :channel, :inserted_at])
  end
end
