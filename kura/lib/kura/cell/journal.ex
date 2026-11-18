defmodule Kura.Cell.Journal do
  @moduledoc false
  require Ash.Query
  alias Kura.Work.Entry

  def record(cell, channel, input, status, output \\ nil) do
    Ash.create(
      Entry,
      %{cell_id: cell, channel: channel, input: input, status: status, output: output},
      action: :record
    )
  end

  def history(cell, channel) do
    cell
    |> recent(channel)
    |> Ash.Query.limit(30)
    |> Ash.read!()
    |> Enum.reverse()
  end

  def latest_command(cell) do
    cell
    |> recent("command")
    |> Ash.Query.limit(1)
    |> Ash.read_one!()
  end

  defp recent(cell, channel) do
    Entry
    |> Ash.Query.filter(cell_id == ^cell and channel == ^channel)
    |> Ash.Query.sort(inserted_at: :desc, id: :desc)
  end

  def finish(entry, result, trace \\ nil)

  def finish(entry, result, trace) do
    {:ok, finished} = resolve(entry, result, trace)
    finished
  end

  def resolve(entry, {:ok, output}, trace), do: resolve(entry, "completed", output, trace)

  def resolve(entry, {:error, reason}, trace) do
    output = if is_binary(reason), do: reason, else: inspect(reason, limit: 10)
    resolve(entry, "blocked", output, trace)
  end

  defp resolve(entry, status, output, trace) do
    Ash.update(entry, %{status: status, output: output, trace: trace}, action: :finish)
  end
end
