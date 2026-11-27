defmodule Pickle.Repo.Migrations.UpgradeJidoka do
  use Ecto.Migration

  def up, do: Jidoka.Migrator.up(version: 10)
  def down, do: Jidoka.Migrator.down(version: 10)
end
