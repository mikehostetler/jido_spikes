defmodule Kura.WorkspaceInspection do
  @moduledoc "Inspects the read-only workspace brief when a cell receives an inspect command."
  @behaviour Jido.Holon.Pulse

  alias Kura.Cell.{Cognition, Control, Journal, Workspace, WorkspaceTool}

  @impl true
  def run(cell, workspace, entry) do
    with ["read_brief", "check_brief"] <- Map.get(cell.playbooks, "inspect"),
         true <- Enum.all?(["workspace_read", "digest"], &(&1 in cell.capabilities)),
         {:ok, receipt} <- Control.authorize(cell, entry.id) do
      {result, trace} = inspect_brief(cell, workspace)
      {with_receipt(result, receipt), trace}
    else
      {:error, _} = error -> {error, nil}
      _ -> {{:error, :inspect_playbook_unavailable}, nil}
    end
  end

  defp inspect_brief(cell, workspace) do
    if Cognition.model(cell) do
      model_inspection(cell, workspace)
    else
      result =
        case Workspace.inspect_brief(workspace, cell.id) do
          {:ok, %{"has_content" => true, "sha256" => digest}} ->
            {:ok, "/brief.txt has content. SHA-256 #{digest}"}

          {:ok, %{"has_content" => false}} ->
            {:error, :empty_brief}

          {:error, _} = error ->
            error
        end

      {result, %{"status" => "local_demo", "tools" => []}}
    end
  end

  defp model_inspection(cell, workspace) do
    with {:ok, skills} <- Cognition.skill_context(cell) do
      memories = cell.memories ++ Enum.map(Journal.history(cell.id, "memory"), & &1.input)

      previous =
        cell.id
        |> Journal.history("command")
        |> Enum.reverse()
        |> Enum.find_value("None", fn record ->
          if record.status == "completed", do: record.output
        end)

      trace =
        Cognition.pulse(
          cell,
          "Inspect this cell's workspace brief. Give the operator a short result.\n\nCell memories:\n#{Enum.join(memories, "\n")}\n\nPrevious outcome (historical):\n#{previous}",
          """
          You are deciding how to inspect the current workspace brief. Use read_workspace_brief
          if you need current evidence. Old notes and outcomes are context only. If you skip the tool,
          explain why and leave the current file status unverified. Use the tool result for current facts.

          #{skills}
          """,
          %{jido_ai_tool_sources: [{WorkspaceTool, cell.id}], kura_workspace: workspace},
          %{requirement: :optional, visible: ["read_workspace_brief"]}
        )

      {work_result(trace), trace}
    else
      {:error, _} = error -> {error, nil}
    end
  end

  defp work_result(%{"status" => "completed", "output" => output, "tools" => []})
       when is_binary(output),
       do: {:ok, "Workspace unverified. The model did not call the tool.\n" <> output}

  defp work_result(%{
         "status" => "completed",
         "output" => output,
         "tools" => [%{"status" => "ok"}]
       })
       when is_binary(output),
       do: {:ok, output}

  defp work_result(%{
         "status" => "completed",
         "output" => output,
         "tools" => [%{"status" => "error"}]
       })
       when is_binary(output),
       do: {:error, output}

  defp work_result(trace), do: {:error, trace["reason"] || :cognition_incomplete}

  defp with_receipt({:ok, output}, receipt), do: {:ok, output <> "\nControl: " <> receipt}
  defp with_receipt(error, _receipt), do: error
end
