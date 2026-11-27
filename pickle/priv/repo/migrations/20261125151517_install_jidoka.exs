defmodule Pickle.Repo.Migrations.InstallJidoka do
  use Ecto.Migration

  def up, do: Jidoka.Migrator.up(version: 9)
  def down, do: Jidoka.Migrator.down(version: 1)
end
