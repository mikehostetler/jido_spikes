defmodule JidoWork.FullSkillSource do
  @moduledoc """
  Extends the Jido v3 root skill loader with bounded resource loading.

  Root discovery and `SKILL.md` parsing stay owned by `Jido.AI.Skill`. This
  adapter adds the progressive-disclosure resource boundary that the complete
  Jido and Tutor skills need.
  """

  @behaviour Jido.AI.ToolSource

  alias Jido.AI.Skill
  alias JidoWork.Workspace

  @max_resources 500
  @max_text_bytes 262_144

  def source(roots) when is_list(roots),
    do: {__MODULE__, %{roots: Enum.map(roots, &Path.expand/1)}}

  def catalog(roots) do
    with {:ok, skills} <- Skill.discover(roots) do
      {:ok,
       Enum.map(skills, fn skill ->
         count =
           case resource_manifest(roots, skill.name) do
             {:ok, resources} -> length(resources)
             _error -> 0
           end

         Map.put(skill, :resource_count, count)
       end)}
    end
  end

  @impl true
  def list_tools(config, context) do
    with {:ok, roots} <- roots(config),
         {:ok, native_tools} <- Skill.list_tools(%{roots: roots}, context) do
      tools =
        Enum.map(native_tools, fn tool ->
          Map.update!(tool, :description, fn description ->
            description <>
              "\nThe result also includes a resource manifest. Use load_skill_resource for referenced files."
          end)
        end)

      {:ok, tools ++ [resource_tool()]}
    end
  end

  @impl true
  def run_tool(%{name: "load_skill", arguments: arguments} = call, config, context) do
    with {:ok, roots} <- roots(config),
         {:ok, loaded} <- Skill.run_tool(call, %{roots: roots}, context),
         {:ok, resources} <- resource_manifest(roots, loaded.name) do
      result =
        Map.merge(loaded, %{
          resource_root: "priv/skills/#{loaded.name}",
          resources: resources,
          resource_count: length(resources),
          resource_loading:
            "Call load_skill_resource with this skill name and a relative resource path."
        })

      :ok = Workspace.mark_skill_loaded(loaded.name)
      Workspace.record_event("load_skill", arguments, result)
      {:ok, result}
    end
  end

  def run_tool(%{name: "load_skill_resource", arguments: arguments}, config, _context) do
    with {:ok, roots} <- roots(config),
         {:ok, name} <- required_string(arguments, :name),
         {:ok, path} <- required_string(arguments, :path),
         {:ok, skill_dir} <- skill_directory(roots, name),
         {:ok, full_path} <- safe_resource_path(skill_dir, path),
         {:ok, stat} <- File.lstat(full_path),
         :ok <- regular_file(stat),
         :ok <- within_size(stat.size),
         {:ok, content} <- File.read(full_path),
         :ok <- valid_text(content) do
      result = %{name: name, path: path, content: content, bytes: byte_size(content)}
      :ok = Workspace.mark_skill_resource_loaded(name, path)
      Workspace.record_event("load_skill_resource", arguments, result)
      {:ok, result}
    else
      {:error, reason} = error ->
        Workspace.record_event("load_skill_resource", arguments, error)
        {:error, %{type: :skill_resource_error, reason: reason}}
    end
  end

  def run_tool(%{name: name}, _config, _context), do: {:error, {:unknown_skill_tool, name}}
  def run_tool(_call, _config, _context), do: {:error, :invalid_skill_tool_call}

  defp resource_tool do
    %{
      name: "load_skill_resource",
      description: """
      Load one UTF-8 text file from an active skill package. Use the relative path from the
      resource manifest returned by load_skill. This tool rejects absolute paths, traversal,
      symlinks, non-text files, and files larger than #{@max_text_bytes} bytes.
      """,
      parameter_schema: [
        name: [type: :string, required: true, doc: "Exact loaded skill name"],
        path: [type: :string, required: true, doc: "Relative resource path from the manifest"]
      ]
    }
  end

  defp resource_manifest(roots, name) do
    with {:ok, skill_dir} <- skill_directory(roots, name) do
      resources =
        skill_dir
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.reduce([], fn path, entries ->
          case File.lstat(path) do
            {:ok, %File.Stat{type: :regular, size: size}} ->
              relative = Path.relative_to(path, skill_dir)

              if relative == "SKILL.md" do
                entries
              else
                [%{path: relative, bytes: size, type: resource_type(relative)} | entries]
              end

            _other ->
              entries
          end
        end)
        |> Enum.sort_by(& &1.path)

      if length(resources) <= @max_resources,
        do: {:ok, resources},
        else: {:error, {:too_many_resources, length(resources), @max_resources}}
    end
  end

  defp skill_directory(roots, name) do
    with {:ok, skills} <- Skill.discover(roots),
         true <- Enum.any?(skills, &(&1.name == name)) do
      case Enum.find_value(roots, fn root ->
             directory = Path.join(root, name)
             if File.regular?(Path.join(directory, "SKILL.md")), do: directory
           end) do
        nil -> {:error, {:unknown_skill, name}}
        directory -> {:ok, directory}
      end
    else
      false -> {:error, {:unknown_skill, name}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_resource_path(skill_dir, path) do
    parts = Path.split(path)

    cond do
      Path.type(path) != :relative ->
        {:error, :absolute_path_rejected}

      parts == [] or Enum.any?(parts, &(&1 in [".", "..", ""])) ->
        {:error, :path_traversal_rejected}

      true ->
        walk_regular_path(skill_dir, parts)
    end
  end

  defp walk_regular_path(root, parts) do
    Enum.reduce_while(parts, {:ok, root}, fn part, {:ok, current} ->
      next = Path.join(current, part)

      case File.lstat(next) do
        {:ok, %File.Stat{type: :symlink}} -> {:halt, {:error, :symlink_rejected}}
        {:ok, _stat} -> {:cont, {:ok, next}}
        {:error, reason} -> {:halt, {:error, {:resource_unavailable, reason}}}
      end
    end)
  end

  defp regular_file(%File.Stat{type: :regular}), do: :ok
  defp regular_file(_stat), do: {:error, :not_a_regular_file}

  defp within_size(size) when size <= @max_text_bytes, do: :ok
  defp within_size(size), do: {:error, {:resource_too_large, size, @max_text_bytes}}

  defp valid_text(content) do
    if String.valid?(content), do: :ok, else: {:error, :resource_is_not_utf8_text}
  end

  defp roots(%{roots: roots}) when is_list(roots), do: {:ok, roots}
  defp roots(%{"roots" => roots}) when is_list(roots), do: {:ok, roots}
  defp roots(_config), do: {:error, :invalid_skill_roots}

  defp required_string(arguments, key) when is_map(arguments) do
    case Map.get(arguments, key, Map.get(arguments, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid_argument, key}}
    end
  end

  defp resource_type("references/" <> _rest), do: :reference
  defp resource_type("scripts/" <> _rest), do: :script
  defp resource_type("assets/" <> _rest), do: :asset
  defp resource_type(_path), do: :resource
end
