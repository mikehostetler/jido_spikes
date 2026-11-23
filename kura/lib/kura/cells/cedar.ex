defmodule Kura.Cells.Cedar do
  require Kura.Cell.Control.Adapter
  use Jido.Holon, vsm: true, name: "cedar", description: "Cedar"

  def pulse_handlers do
    %{
      "inspect" => Kura.WorkspaceInspection,
      "Inspect workspace" => Kura.WorkspaceInspection,
      "ci_snapshot" => Kura.Maintenance.Pulse,
      "review_reply" => Kura.Maintenance.Pulse,
      "case_closed" => Kura.Maintenance.Pulse
    }
  end

  def playbook_tasks, do: %{"ci_triage" => Kura.Playbooks.Triage.registration()}

  holon do
    role("cedar/ROLE.md")
    capabilities(["workspace_read", "digest", "ci_triage"])
    signals(%{"kura.workspace.inspect" => "inspect"})
    skills(["jido"])
    memories(["Cedar assigns cases to three Review cells with separate workspaces."])
    playbooks(%{"inspect" => ["read_brief", "check_brief"]})

    children(%{
      "review" => Kura.Cells.Inspector,
      "review-2" => Kura.Cells.Inspector,
      "review-3" => Kura.Cells.Inspector
    })
  end

  vsm do
    operation(:delivery)
    operation(:readiness)
    adapter(Kura.Cell.Control.Adapter)
  end
end
