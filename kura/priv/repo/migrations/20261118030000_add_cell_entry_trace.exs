defmodule Kura.Repo.Migrations.AddCellEntryTrace do
  use Ecto.Migration

  def change do
    alter table(:cell_entries) do
      add :trace, :map
    end
  end
end
