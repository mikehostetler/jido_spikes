defmodule Section9.SkillSource do
  @moduledoc "Jido skill source with bounded progressive resource loading."

  @behaviour Jido.AI.ToolSource

  alias Jido.AI.Skill

  @max_resources 500
  @max_text_bytes 262_144

  def source(roots) when is_list(roots),
    do: {__MODULE__, %{roots: Enum.map(roots, &Path.expand/1)}}

  @impl true
  def list_tools(config, context) do
    with {:ok, roots} <- roots(config),
         {:ok, tools} <- Skill.list_tools(%{roots: roots}, context) do
      tools =
        Enum.map(tools, fn tool ->
          Map.update!(tool, :description, fn description ->
            description <>
              "\nThe result includes a resource manifest. Load named references with load_skill_resource."
          end)
        end)

      {:ok, tools ++ [resource_tool()]}
    end
  end

  @impl true
  def run_tool(%{name: "load_skill"} = call, config, context) do
    with {:ok, roots} <- roots(config),
         {:ok, loaded} <- Skill.run_tool(call, %{roots: roots}, context),
         {:ok, resources} <- manifest(roots, loaded.name) do
      {:ok,
       Map.merge(loaded, %{
         resources: resources,
         resource_count: length(resources),
         resource_loading: "Call load_skill_resource with the exact relative path."
       })}
    end
  end

  def run_tool(%{name: "load_skill_resource", arguments: arguments}, config, _context) do
    with {:ok, roots} <- roots(config),
         {:ok, name} <- required(arguments, :name),
         {:ok, path} <- required(arguments, :path),
         {:ok, skill_dir} <- skill_directory(roots, name),
         {:ok, full_path} <- safe_path(skill_dir, path),
         {:ok, %File.Stat{type: :regular, size: size}} <- File.lstat(full_path),
         true <- size <= @max_text_bytes,
         {:ok, content} <- File.read(full_path),
         true <- String.valid?(content) do
      {:ok, %{name: name, path: path, content: content, bytes: size}}
    else
      false -> {:error, :invalid_or_large_skill_resource}
      {:ok, _other} -> {:error, :skill_resource_not_regular}
      {:error, reason} -> {:error, reason}
    end
  end

  def run_tool(%{name: name}, _config, _context), do: {:error, {:unknown_skill_tool, name}}
  def run_tool(_call, _config, _context), do: {:error, :invalid_skill_tool_call}

  def manifest(roots, name) do
    with {:ok, skill_dir} <- skill_directory(roots, name) do
      resources =
        skill_dir
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.flat_map(fn path ->
          case File.lstat(path) do
            {:ok, %File.Stat{type: :regular, size: size}} ->
              relative = Path.relative_to(path, skill_dir)
              if relative == "SKILL.md", do: [], else: [%{path: relative, bytes: size}]

            _ ->
              []
          end
        end)
        |> Enum.sort_by(& &1.path)

      if length(resources) <= @max_resources,
        do: {:ok, resources},
        else: {:error, {:too_many_resources, length(resources)}}
    end
  end

  defp resource_tool do
    %{
      name: "load_skill_resource",
      description:
        "Load one UTF-8 text resource from a loaded skill. Absolute paths, traversal, symlinks, and large files are rejected.",
      parameter_schema: [
        name: [type: :string, required: true],
        path: [type: :string, required: true]
      ]
    }
  end

  defp skill_directory(roots, name) do
    case Enum.find_value(roots, fn root ->
           directory = Path.join(root, name)
           if File.regular?(Path.join(directory, "SKILL.md")), do: directory
         end) do
      nil -> {:error, {:unknown_skill, name}}
      directory -> {:ok, directory}
    end
  end

  defp safe_path(root, path) do
    parts = Path.split(path)

    cond do
      Path.type(path) != :relative ->
        {:error, :absolute_path_rejected}

      parts == [] or Enum.any?(parts, &(&1 in [".", "..", ""])) ->
        {:error, :path_traversal_rejected}

      true ->
        walk(root, parts)
    end
  end

  defp walk(root, parts) do
    Enum.reduce_while(parts, {:ok, root}, fn part, {:ok, current} ->
      path = Path.join(current, part)

      case File.lstat(path) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :symlink_rejected}}
        {:ok, _} -> {:cont, {:ok, path}}
        {:error, reason} -> {:halt, {:error, {:resource_unavailable, reason}}}
      end
    end)
  end

  defp required(arguments, key) when is_map(arguments) do
    case Map.get(arguments, key, Map.get(arguments, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> {:error, {:invalid_argument, key}}
    end
  end

  defp roots(%{roots: roots}) when is_list(roots), do: {:ok, roots}
  defp roots(%{"roots" => roots}) when is_list(roots), do: {:ok, roots}
  defp roots(_), do: {:error, :invalid_skill_roots}
end

defmodule Section9.SkillPackage do
  @moduledoc "Loads and records the trusted Jido skill package for every actor identity."

  def root, do: Application.app_dir(:section9, "priv/skills")
  def source, do: Section9.SkillSource.source([root()])

  def load_all do
    Enum.each(Section9.RolePolicy.roles(), &load_for/1)
    :ok
  end

  def load_for(role) do
    with {:ok, skill} <- Jido.AI.Skill.load([root()], "jido"),
         {:ok, commands} <- File.read(Path.join([root(), "jido", "references", "commands.md"])),
         {:ok, resources} <- Section9.SkillSource.manifest([root()], "jido") do
      Section9.Ledger.record_skill_load(role, %{
        name: skill.name,
        root_digest: digest(skill.instructions),
        resources: [
          %{path: "SKILL.md", digest: digest(skill.instructions)},
          %{path: "references/commands.md", digest: digest(commands)},
          %{manifest_count: length(resources)}
        ]
      })
    end
  end

  defp digest(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
end
