defmodule JidoWorkSystem.Store do
  @moduledoc false

  def all(resource) do
    resource
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  def last(resource) do
    resource
    |> Ash.Query.sort(inserted_at: :desc)
    |> Ash.Query.limit(1)
    |> Ash.read!()
    |> List.first()
  end

  def get(resource, id) do
    case Ash.get(resource, id) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, record} -> {:ok, record}
      {:error, _error} -> {:error, :not_found}
    end
  end

  def get!(resource, id), do: Ash.get!(resource, id)

  def where(resource, attribute, value) do
    resource
    |> Ash.Query.filter_input(%{attribute => value})
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  def where_in(_resource, _attribute, []), do: []

  def where_in(resource, attribute, values) do
    resource
    |> Ash.Query.filter_input(%{attribute => %{"in" => values}})
    |> Ash.Query.sort(inserted_at: :asc)
    |> Ash.read!()
  end

  def create!(resource, attrs) do
    changeset = Ash.Changeset.new(resource)

    changeset =
      Enum.reduce(attrs, changeset, fn {attribute, value}, changeset ->
        Ash.Changeset.force_change_attribute(changeset, attribute, value)
      end)

    changeset
    |> Ash.Changeset.for_create(:create, %{})
    |> Ash.create!()
  end

  def update!(record, attrs) do
    record
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!()
  end
end
