defmodule Jarvis.Repo.Migrations.AddTypedMemoryAndFts do
  use Ecto.Migration

  def up do
    alter table(:memories) do
      add :namespace, :string, null: false, default: "user"
      add :class, :string, null: false, default: "semantic"
      add :metadata, :map, null: false, default: %{}
      add :superseded_by_id, references(:memories, on_delete: :nilify_all)
      add :forgotten_at, :utc_datetime
    end

    create index(:memories, [:namespace, :class])
    create index(:memories, [:superseded_by_id])
    create index(:memories, [:forgotten_at])

    execute("""
    CREATE VIRTUAL TABLE memories_fts USING fts5(
      title,
      content,
      content='memories',
      content_rowid='id',
      tokenize='unicode61'
    )
    """)

    execute("""
    CREATE TRIGGER memories_fts_insert AFTER INSERT ON memories BEGIN
      INSERT INTO memories_fts(rowid, title, content)
      VALUES (new.id, new.title, new.content);
    END
    """)

    execute("""
    CREATE TRIGGER memories_fts_delete AFTER DELETE ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, title, content)
      VALUES ('delete', old.id, old.title, old.content);
    END
    """)

    execute("""
    CREATE TRIGGER memories_fts_update AFTER UPDATE OF title, content ON memories BEGIN
      INSERT INTO memories_fts(memories_fts, rowid, title, content)
      VALUES ('delete', old.id, old.title, old.content);
      INSERT INTO memories_fts(rowid, title, content)
      VALUES (new.id, new.title, new.content);
    END
    """)

    execute("INSERT INTO memories_fts(memories_fts) VALUES ('rebuild')")
  end

  def down do
    execute("DROP TRIGGER IF EXISTS memories_fts_update")
    execute("DROP TRIGGER IF EXISTS memories_fts_delete")
    execute("DROP TRIGGER IF EXISTS memories_fts_insert")
    execute("DROP TABLE IF EXISTS memories_fts")

    drop_if_exists index(:memories, [:forgotten_at])
    drop_if_exists index(:memories, [:superseded_by_id])
    drop_if_exists index(:memories, [:namespace, :class])

    alter table(:memories) do
      remove :forgotten_at
      remove :superseded_by_id
      remove :metadata
      remove :class
      remove :namespace
    end
  end
end
