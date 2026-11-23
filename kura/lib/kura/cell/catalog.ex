defmodule Kura.Cell.Catalog do
  @moduledoc false

  alias Kura.Cell.{Bindings, Definition}

  @builtins [{"cedar", Kura.Cells.Cedar}, {"pine", Kura.Cells.Pine}]

  def builtin_id?(id), do: List.keymember?(@builtins, id, 0)

  def all, do: builtins() ++ Enum.map(Definition.all(), &load!/1)

  def fetch(id) when is_binary(id) do
    case Enum.find(builtins(), &(&1.id == id)) || Definition.fetch(id) do
      nil -> {:error, :unknown_cell}
      %Definition.Record{} = record -> load(record)
      cell -> {:ok, cell}
    end
  end

  def fetch(_), do: {:error, :unknown_cell}

  defp builtins do
    Enum.flat_map(@builtins, fn {id, module} -> expand(id, nil, module) end)
  end

  defp expand(id, parent, module) do
    definition = module.definition()
    {:ok, profile} = Jido.Holon.profile(definition)

    cell =
      id
      |> cell(parent, definition, profile)
      |> Map.merge(%{
        agent_source: module,
        pulse_handlers: module.pulse_handlers(),
        playbook_tasks: module.playbook_tasks(),
        workspace: %{"policy" => "read_only"},
        cognition: "inherit"
      })

    [
      cell
      | Enum.flat_map(Enum.sort(profile["children"]), fn {slot, child} ->
          expand(id <> "/" <> slot, id, child)
        end)
    ]
  end

  defp load!(record) do
    {:ok, cell} = load(record)
    cell
  end

  defp load(record) do
    with {:ok, %{module: nil} = definition} <- Definition.load(record),
         {:ok, %{"runtime" => runtime} = profile} <- Jido.Holon.profile(definition),
         {:ok, {handlers, tasks}} <- Bindings.resolve(profile) do
      {:ok,
       record.id
       |> cell(record.parent, definition, profile)
       |> Map.merge(%{
         agent_source: definition,
         pulse_handlers: handlers,
         playbook_tasks: tasks,
         workspace: runtime["workspace"],
         cognition: runtime["cognition"]
       })}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_stored_cell}
    end
  end

  defp cell(id, parent, definition, profile) do
    %{
      id: id,
      parent: parent,
      name: definition.description,
      definition: definition,
      module: definition.module,
      role_text: role_text(profile["role"]),
      capabilities: profile["capabilities"],
      skills: profile["skills"],
      memories: profile["memories"],
      playbooks: profile["playbooks"],
      signals: profile["signals"]
    }
  end

  defp role_text(%{"text" => text}), do: text

  defp role_text(path) do
    :kura |> Application.app_dir(Path.join("priv/cells", path)) |> File.read!()
  end
end
