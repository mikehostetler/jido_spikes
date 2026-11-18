defmodule Kura.Cell.Inbox do
  @moduledoc "Persists work events by cell and, optionally, by a workflow instance."
  require Ash.Query

  alias Kura.Work.Entry

  # Enqueue within the same transaction as the state change that produced the event.
  # Wake the cell only after the transaction commits.
  def enqueue(cell, kind, payload, opts \\ []) do
    Ash.create(
      Entry,
      %{
        id: Keyword.get_lazy(opts, :id, &Ash.UUID.generate/0),
        cell_id: cell,
        channel: Keyword.get(opts, :channel, "pulse"),
        input: Keyword.get(opts, :input, kind),
        status: "queued",
        kind: kind,
        scope_id: opts[:scope_id],
        payload: payload
      },
      action: :enqueue
    )
  end

  def next(cell) do
    queued()
    |> Ash.Query.filter(cell_id == ^cell)
    |> Ash.Query.sort([:inserted_at, :id])
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
  end

  def queued_cells do
    queued()
    |> Ash.Query.select([:cell_id])
    |> Ash.read!()
    |> Enum.map(& &1.cell_id)
    |> Enum.uniq()
  end

  def scoped_events(cell, scope_id) do
    Entry
    |> Ash.Query.filter(cell_id == ^cell and scope_id == ^scope_id and channel == "pulse")
    |> Ash.Query.sort([:inserted_at, :id])
    |> Ash.read!()
  end

  defp queued do
    Ash.Query.filter(Entry, channel in ["command", "pulse"] and status == "queued")
  end
end
