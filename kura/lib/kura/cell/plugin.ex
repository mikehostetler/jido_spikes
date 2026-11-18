defmodule Kura.Cell.Plugin do
  @moduledoc "Jido authoring contribution for a Durable Work Cell."
  alias Kura.Cell.Bindings
  alias Spark.Dsl.Extension, as: DSL

  @fields [
    role: [type: :string, required: true],
    capabilities: [type: {:list, :string}, default: []],
    signals: [type: {:map, :string, :string}, default: %{}],
    skills: [type: {:list, :string}, default: []],
    memories: [type: {:list, :string}, default: []],
    playbooks: [type: {:map, :string, {:list, :string}}, default: %{}],
    children: [type: {:map, :string, :atom}, default: %{}]
  ]
  @section %Spark.Dsl.Section{name: :cell, schema: @fields}

  use Jido.Plugin, id: "kura/cell", vsn: 1, sections: [@section]

  @impl true
  def lower(dsl, config) when map_size(config) == 0 do
    data =
      Map.new(@fields, fn {key, spec} ->
        {Atom.to_string(key), DSL.get_opt(dsl, [:cell], key, spec[:default])}
      end)

    normalize(data)
  end

  def lower(_dsl, config), do: normalize(config)

  @impl true
  def normalize(
        %{
          "role" => role,
          "capabilities" => capabilities,
          "signals" => signals,
          "skills" => skills,
          "memories" => memories,
          "playbooks" => playbooks,
          "children" => children
        } = data
      )
      when map_size(data) in [7, 8] do
    if valid_role?(role) and strings?(capabilities) and strings?(skills) and
         strings?(memories) and
         pairs?(signals, &is_binary/1) and pairs?(playbooks, &strings?/1) and
         valid_source?(data, children) do
      {:ok, data}
    else
      invalid()
    end
  end

  def normalize(_), do: invalid()

  @impl true
  def verify(_data, definition) do
    if Enum.any?(definition.plugins, &(&1.provider == Jido.VSM.Cell.Plugin)),
      do: :ok,
      else: invalid()
  end

  defp valid_source?(%{"runtime" => runtime} = data, children) do
    is_map(runtime) and Enum.sort(Map.keys(runtime)) == ~w(cognition handlers tasks workspace) and
      match?(%{"text" => _}, data["role"]) and pairs?(children, &is_binary/1) and
      match?({:ok, _}, Bindings.resolve(data))
  end

  defp valid_source?(data, children) when map_size(data) == 7 do
    is_binary(data["role"]) and pairs?(children, &(is_atom(&1) and &1 not in [nil, true, false]))
  end

  defp valid_source?(_, _), do: false

  defp valid_role?(%{"text" => text} = role) when is_binary(text),
    do: map_size(role) == 1 and byte_size(text) <= 16_384 and String.trim(text) != ""

  defp valid_role?(role) when is_binary(role),
    do: Regex.match?(~r/\A[a-z0-9_-]+\/ROLE\.md\z/, role)

  defp valid_role?(_), do: false
  defp strings?(items), do: is_list(items) and Enum.all?(items, &is_binary/1)

  defp pairs?(map, value?) do
    is_map(map) and not is_struct(map) and
      Enum.all?(map, fn {key, value} -> is_binary(key) and value?.(value) end)
  end

  defp invalid do
    Jido.Error.validation_result(:invalid_kura_cell, [:cell], "Invalid Kura Cell definition")
  end
end
