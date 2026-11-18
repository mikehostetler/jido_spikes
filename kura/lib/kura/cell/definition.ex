defmodule Kura.Cell.Definition do
  @moduledoc "Imports local Cell declarations and stores canonical Jido Agent documents."

  alias Jido.{Agent, Codec}
  alias Kura.Cell.{Catalog, Control, Plugin, References}
  alias Kura.Repo

  @fields ~w(name role capabilities signals skills memories playbooks children handlers tasks workspace cognition vsm)
  @id ~r/\A[a-z][a-z0-9_-]{0,47}\z/

  defmodule Record do
    use Ecto.Schema

    @primary_key {:id, :string, autogenerate: false}
    schema "cell_definitions" do
      field :parent, :string
      field :document, :map
    end
  end

  def import_json(json) when is_binary(json) and byte_size(json) <= 262_144 do
    with {:ok, %{"id" => id, "version" => 1} = source} <-
           Jido.Codec.Document.decode_json(json, 262_144),
         true <- valid_id?(id),
         false <- Catalog.builtin_id?(id),
         {:ok, records} <-
           compile_tree(id, nil, Map.drop(source, ["id", "version"]), 0, codec_opts()) do
      Repo.transact(fn ->
        Enum.reduce_while(records, {:ok, id}, fn record, result ->
          case Repo.insert_all(Record, [record], on_conflict: :nothing, conflict_target: [:id]) do
            {1, _} -> {:cont, result}
            {0, _} -> {:halt, {:error, {:cell_already_exists, record.id}}}
          end
        end)
      end)
    else
      true -> {:error, :reserved_cell_id}
      {:error, _} = error -> error
      _ -> {:error, :invalid_cell_definition}
    end
  end

  def import_json(_), do: {:error, :invalid_cell_definition}

  def fetch(id), do: Repo.get(Record, id)
  def all, do: Repo.all(Record)

  def load(%Record{} = record), do: Codec.decode(record.document, codec_opts())

  def export(definition), do: Codec.encode_json(definition, codec_opts())

  defp codec_opts, do: [codec: Jido.Agent.Codec, catalog: References.definition_catalog()]

  defp compile_tree(id, parent, source, depth, codec)
       when is_map(source) and depth <= 5 do
    children = Map.get(source, "children", %{})

    with true <- Map.keys(source) -- @fields == [],
         true <- valid_name?(Map.get(source, "name", id)),
         true <- is_map(children) and Enum.all?(Map.keys(children), &valid_id?/1),
         {:ok, data} <- profile(id, source, children),
         {:ok, vsm} <- vsm(source, id),
         {:ok, definition} <-
           Agent.define(%{
             vsm
             | description: Map.get(source, "name", id),
               plugins: vsm.plugins ++ [%{id: "kura/cell", vsn: 1, provider: Plugin, data: data}]
           }),
         {:ok, document} <- Codec.encode(definition, codec) do
      Enum.reduce_while(
        Enum.sort(children),
        {:ok, [%{id: id, parent: parent, document: document}]},
        fn
          {slot, child}, {:ok, records} ->
            case compile_tree(id <> "/" <> slot, id, child, depth + 1, codec) do
              {:ok, nodes} -> {:cont, {:ok, records ++ nodes}}
              error -> {:halt, error}
            end
        end
      )
    else
      false -> {:error, {:invalid_cell_definition, id}}
      error -> error
    end
  end

  defp compile_tree(id, _parent, _source, _depth, _codec),
    do: {:error, {:invalid_cell_definition, id}}

  defp profile(id, source, children) do
    runtime = %{
      "handlers" => Map.get(source, "handlers", %{}),
      "tasks" => Map.get(source, "tasks", %{}),
      "workspace" => Map.get(source, "workspace", %{"policy" => "read_only"}),
      "cognition" => Map.get(source, "cognition", "local")
    }

    data = %{
      "role" => %{"text" => source["role"]},
      "capabilities" => Map.get(source, "capabilities", []),
      "signals" => Map.get(source, "signals", %{}),
      "skills" => Map.get(source, "skills", []),
      "memories" => Map.get(source, "memories", []),
      "playbooks" => Map.get(source, "playbooks", %{}),
      "children" => Map.new(children, fn {slot, _} -> {slot, id <> "/" <> slot} end),
      "runtime" => runtime
    }

    Plugin.normalize(data)
  end

  # Named topology profiles keep adapter code and grants under operator control.
  defp vsm(source, id) do
    case Map.get(source, "vsm", "standard") do
      "standard" ->
        Control.standard_definition(Path.basename(id))

      _ ->
        {:error, {:unknown_vsm_profile, id}}
    end
  end

  defp valid_name?(name),
    do: is_binary(name) and byte_size(name) <= 160 and String.trim(name) != ""

  defp valid_id?(id), do: is_binary(id) and Regex.match?(@id, id)
end
