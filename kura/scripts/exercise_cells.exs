defmodule Kura.ExerciseCells do
  alias Jido.Signal.Bus
  alias Kura.Cells

  def run do
    model = Application.get_env(:kura, :cell_model)
    IO.puts("Cognition: #{model || "deterministic local demo"}")

    buses =
      Map.new(Cells.all(), fn cell ->
        bus = unwrap(Cells.bus(cell.id), "Open bus for #{cell.id}")
        IO.puts("#{cell.id} | parent: #{cell.parent || "none"} | bus: #{inspect(bus)}")
        {cell.id, bus}
      end)

    unique_buses = buses |> Map.values() |> Enum.uniq()

    if map_size(buses) != length(unique_buses) do
      Mix.raise("Cells share a signal bus")
    end

    note =
      unwrap(
        Cells.remember("cedar/review", "Exercise script: verify the local brief."),
        "Save memory"
      )

    IO.puts("\nMemory saved in #{note.cell_id}: #{note.input}")

    demands =
      for id <- Map.keys(buses) |> Enum.sort() do
        entry = unwrap(inspect_workspace(id), "Queue inspection for #{id}")
        {id, entry.id}
      end

    deadline = System.monotonic_time(:millisecond) + 60_000

    for {id, entry_id} <- demands do
      entry = await_work(id, entry_id, deadline)
      IO.puts("\n#{id} | #{entry.status}\n#{entry.output}")
    end

    reply =
      unwrap(
        Cells.chat("cedar/review", "What did your workspace inspection find?"),
        "Chat with Review"
      )

    IO.puts("\nChat with #{reply.cell_id}\n#{reply.output}")

    for {id, _entry_id} <- demands do
      bus = Map.fetch!(buses, id)
      events = unwrap(Bus.replay(bus, "kura.cell.**"), "Read bus events for #{id}")
      types = Enum.map_join(events, ", ", &"#{&1.signal.type} (#{&1.signal.data.status})")
      IO.puts("#{id} events: #{types}")
    end

    IO.puts("\nJournal saved to the development database. Open or reload /cells to see it.")
  end

  defp inspect_workspace("cedar/review" = id) do
    signal = Jido.Signal.new!("kura.workspace.inspect", %{}, source: "/kura/exercise")
    Cells.signal(id, signal)
  end

  defp inspect_workspace(id), do: Cells.command(id, :inspect)

  defp await_work(id, entry_id, deadline) do
    entry = Enum.find(Cells.history(id, "command"), &(&1.id == entry_id))

    case entry do
      %{status: "completed"} ->
        entry

      %{status: "blocked", output: output} ->
        Mix.raise("#{id} inspection blocked: #{output}")

      _ ->
        if System.monotonic_time(:millisecond) >= deadline do
          Mix.raise("#{id} inspection timed out (#{entry_id})")
        end

        Process.sleep(100)
        await_work(id, entry_id, deadline)
    end
  end

  defp unwrap({:ok, value}, _operation), do: value
  defp unwrap({:error, reason}, operation), do: Mix.raise("#{operation}: #{inspect(reason)}")
end

if Mix.env() != :dev do
  Mix.raise("Run this script with MIX_ENV=dev to write to the development database")
end

Logger.configure(level: :warning)
Kura.ExerciseCells.run()
