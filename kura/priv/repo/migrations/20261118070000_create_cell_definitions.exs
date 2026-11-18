defmodule Kura.Repo.Migrations.CreateCellDefinitions do
  use Ecto.Migration

  def change do
    create table(:cell_definitions, primary_key: false) do
      add :id, :text, primary_key: true
      add :parent, references(:cell_definitions, type: :text, on_delete: :restrict)
      add :document, :map, null: false
    end
  end
end
