defmodule Kura.WorkspaceToolTest do
  use ExUnit.Case, async: false

  alias Kura.Cell.{Workspace, WorkspaceTool}

  @tag :tmp_dir
  test "reads only the brief from the bound workspace", %{tmp_dir: directory} do
    original_root = Application.fetch_env!(:kura, :cell_workspace_root)
    Application.put_env(:kura, :cell_workspace_root, directory)
    on_exit(fn -> Application.put_env(:kura, :cell_workspace_root, original_root) end)

    cell = "pine"
    assert {:ok, workspace} = Workspace.open(%{id: cell})
    context = %{kura_workspace: workspace}
    call = %{id: "call-1", name: "read_workspace_brief", arguments: %{}}

    expected = "Workspace brief for pine.\n"
    expected_size = byte_size(expected)
    expected_digest = :crypto.hash(:sha256, expected) |> Base.encode16(case: :lower)

    assert {:ok,
            %{"bytes" => ^expected_size, "sha256" => ^expected_digest, "has_content" => true}} =
             WorkspaceTool.run_tool(call, cell, context)

    assert {:error, :invalid_workspace_tool_call} =
             WorkspaceTool.run_tool(
               %{call | arguments: %{"path" => "../other.txt"}},
               cell,
               context
             )

    brief = Path.join([directory, Base.url_encode64(cell, padding: false), "brief.txt"])
    outside = Path.join(directory, "other.txt")
    File.write!(outside, "Outside the cell")
    File.rm!(brief)
    File.ln_s!(outside, brief)
    assert {:error, :brief_unavailable} = WorkspaceTool.run_tool(call, cell, context)
  end
end
