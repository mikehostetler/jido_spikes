defmodule Kura.Cells.Cedar do
  require Kura.Cell.Control.Adapter
  use Kura.Cell, name: "cedar", description: "Cedar"

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

  cell do
    role("cedar/ROLE.md")
    capabilities(["workspace_read", "digest", "ci_triage"])
    signals(%{"kura.workspace.inspect" => "inspect"})
    skills(["jido"])
    memories(["Cedar has a nested Review cell with a separate workspace."])
    playbooks(%{"inspect" => ["read_brief", "check_brief"]})
    children(%{"review" => Kura.Cells.Inspector})
  end

  vsm do
    operation(:delivery)
    operation(:readiness)
    adapter(Kura.Cell.Control.Adapter)
  end
end
