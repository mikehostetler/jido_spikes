defmodule Jarvis.Memories.Memory do
  @moduledoc "One stored Jarvis memory record."

  use Ecto.Schema
  import Ecto.Changeset

  schema "memories" do
    field(:title, :string)
    field(:content, :string)
    field(:namespace, :string, default: "user")
    field(:class, :string, default: "semantic")
    field(:metadata, :map, default: %{})
    field(:forgotten_at, :utc_datetime)
    belongs_to(:superseded_by, __MODULE__)

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(memory, attrs) do
    memory
    |> cast(attrs, [
      :title,
      :content,
      :namespace,
      :class,
      :metadata,
      :forgotten_at,
      :superseded_by_id
    ])
    |> validate_required([:title, :content, :namespace, :class, :metadata])
    |> validate_length(:title, max: 200)
    |> validate_length(:content, max: 50_000)
    |> validate_length(:namespace, min: 1, max: 200)
    |> validate_inclusion(:class, ~w(semantic episodic procedural working))
  end
end
