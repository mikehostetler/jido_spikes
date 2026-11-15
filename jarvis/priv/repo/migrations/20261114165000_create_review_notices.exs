defmodule Jarvis.Repo.Migrations.CreateReviewNotices do
  use Ecto.Migration
  def change do
    create table(:review_notices) do
      add :topic, :text, null: false
      add :review_id, :text, null: false
      add :action, :text, null: false
      add :text, :text, null: false
    end
    create index(:review_notices, [:topic, :id])
    create index(:review_notices, [:review_id, :id])
  end
end
