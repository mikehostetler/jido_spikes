defmodule Mix.Tasks.Kura.Cell.Import do
  use Mix.Task

  @shortdoc "Imports a local JSON Cell definition"
  @requirements ["app.start"]

  @impl true
  def run([path]) do
    with {:ok, json} <- File.read(path),
         {:ok, id} <- Kura.Cells.import_definition(json) do
      Mix.shell().info("Imported #{id}")
    else
      {:error, reason} -> Mix.raise("Cell import failed: #{inspect(reason)}")
    end
  end

  def run(_), do: Mix.raise("Usage: mix kura.cell.import PATH")
end
