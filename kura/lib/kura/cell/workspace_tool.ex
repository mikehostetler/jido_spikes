defmodule Kura.Cell.WorkspaceTool do
  @moduledoc false
  @behaviour Jido.AI.ToolSource

  alias Kura.Cell.Workspace

  @impl true
  def list_tools(_config, _context) do
    {:ok,
     [
       %{
         name: "read_workspace_brief",
         description:
           "Read /brief.txt in this cell's workspace. Returns whether it has content, its byte count, and its SHA-256 digest.",
         parameter_schema: []
       }
     ]}
  end

  @impl true
  def run_tool(%{name: "read_workspace_brief", arguments: arguments}, cell_id, %{
        kura_workspace: workspace
      })
      when map_size(arguments) == 0 do
    Workspace.inspect_brief(workspace, cell_id)
  end

  def run_tool(_call, _cell_id, _context), do: {:error, :invalid_workspace_tool_call}
end
