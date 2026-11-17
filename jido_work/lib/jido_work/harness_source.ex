defmodule JidoWork.HarnessSource do
  @moduledoc "Confined Jido VFS and Jido Shell tools for the spike workspace."

  @behaviour Jido.AI.ToolSource

  alias JidoWork.Workspace

  def source, do: {__MODULE__, %{}}

  @impl true
  def list_tools(_config, _context), do: {:ok, tool_definitions()}

  @impl true
  def run_tool(%{name: "list_files", arguments: arguments}, _config, _context) do
    with_skill_gate("list_files", arguments, fn ->
      Workspace.list_files(optional_string(arguments, :pattern, ""))
    end)
  end

  def run_tool(%{name: "read_file", arguments: arguments}, _config, _context) do
    with_skill_gate("read_file", arguments, fn ->
      with {:ok, path} <- required_string(arguments, :path), do: Workspace.read_file(path)
    end)
  end

  def run_tool(%{name: "search_text", arguments: arguments}, _config, _context) do
    with_skill_gate("search_text", arguments, fn ->
      with {:ok, query} <- required_string(arguments, :query),
           do: Workspace.search_text(query)
    end)
  end

  def run_tool(%{name: "edit_file", arguments: arguments}, _config, _context) do
    with_skill_gate("edit_file", arguments, fn ->
      with {:ok, path} <- required_string(arguments, :path),
           {:ok, old_text} <- required_string(arguments, :old_text),
           {:ok, new_text} <- required_string(arguments, :new_text) do
        Workspace.edit_file(path, old_text, new_text)
      end
    end)
  end

  def run_tool(%{name: "run_shell", arguments: arguments}, _config, _context) do
    with_skill_gate("run_shell", arguments, fn ->
      with {:ok, command} <- required_string(arguments, :command),
           do: Workspace.run_shell(command)
    end)
  end

  def run_tool(%{name: name}, _config, _context), do: {:error, {:unknown_harness_tool, name}}
  def run_tool(_call, _config, _context), do: {:error, :invalid_harness_tool_call}

  defp with_skill_gate(tool, arguments, fun) do
    case Workspace.check_skill_gate() do
      :ok ->
        fun.()

      {:error, _reason} = error ->
        Workspace.record_event(tool, arguments, error)
        error
    end
  end

  defp tool_definitions do
    [
      %{
        name: "list_files",
        description:
          "List paths through the confined Jido VFS filesystem. This does not inspect the host filesystem.",
        parameter_schema: [pattern: [type: :string, doc: "Optional path filter or **/*"]]
      },
      %{
        name: "read_file",
        description:
          "Read one project file through Jido VFS. Use load_skill_resource for skill files.",
        parameter_schema: [path: [type: :string, required: true, doc: "VFS project path"]]
      },
      %{
        name: "search_text",
        description: "Find exact text in all files in the confined Jido VFS filesystem.",
        parameter_schema: [query: [type: :string, required: true, doc: "Exact text to find"]]
      },
      %{
        name: "edit_file",
        description:
          "Replace one exact text occurrence in one Jido VFS file with a checked write.",
        parameter_schema: [
          path: [type: :string, required: true, doc: "VFS project path"],
          old_text: [type: :string, required: true, doc: "Exact existing text"],
          new_text: [type: :string, required: true, doc: "Replacement text"]
        ]
      },
      %{
        name: "run_shell",
        description:
          "Run read-only Jido Shell built-ins against the same VFS. Allowed commands: pwd, ls, cat, help.",
        parameter_schema: [command: [type: :string, required: true, doc: "Jido Shell command"]]
      }
    ]
  end

  defp required_string(arguments, key) when is_map(arguments) do
    case Map.get(arguments, key, Map.get(arguments, Atom.to_string(key))) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:invalid_argument, key}}
    end
  end

  defp optional_string(arguments, key, default) do
    case Map.get(arguments, key, Map.get(arguments, Atom.to_string(key), default)) do
      value when is_binary(value) -> value
      _other -> default
    end
  end
end
