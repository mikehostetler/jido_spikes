defmodule Kura.Repo.Migrations.CreateMaintenanceCases do
  use Ecto.Migration

  def change do
    create table(:maintenance_cases, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :state, :map, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end
  end
end
