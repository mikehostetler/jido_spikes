defmodule Kura.Repo.Migrations.CreateCellEntries do
  use Ecto.Migration

  def change do
    create table(:cell_entries, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :cell_id, :text, null: false
      add :channel, :text, null: false
      add :input, :text, null: false
      add :status, :text, null: false
      add :output, :text
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:cell_entries, [:cell_id, :channel, :status, :inserted_at])
  end
end
