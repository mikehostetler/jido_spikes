defmodule Kura.Repo.Migrations.AddPlaybooks do
  use Ecto.Migration

  def change do
    create table(:playbook_versions, primary_key: false) do
      add :id, :text, primary_key: true
      add :cell_id, :text, null: false
      add :task, :text, null: false
      add :revision, :integer, null: false
      add :document, :map, null: false
      add :base_id, :text
      add :evidence, :map, null: false
      add :replay, :map
      add :approved, :boolean, default: false, null: false
      add :active, :boolean, default: false, null: false
    end

    create unique_index(:playbook_versions, [:cell_id, :task], where: "active = 1")

    create table(:loom_records, primary_key: false) do
      add :id, :text, primary_key: true
      add :version_id, :text
      add :revision, :integer, null: false
      add :checkpoint, :binary, null: false
    end
  end
end
