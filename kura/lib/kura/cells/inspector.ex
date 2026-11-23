defmodule Kura.Cells.Inspector do
  require Kura.Cell.Control.Adapter
  use Jido.Holon, vsm: true, name: "workspace_inspector", description: "Workspace inspector"

  def pulse_handlers do
    %{
      "inspect" => Kura.WorkspaceInspection,
      "Inspect workspace" => Kura.WorkspaceInspection,
      "ci_snapshot" => Kura.Maintenance.Pulse,
      "review_reply" => Kura.Maintenance.Pulse,
      "case_closed" => Kura.Maintenance.Pulse
    }
  end

  holon do
    role("inspector/ROLE.md")
    capabilities(["workspace_read", "digest"])
    signals(%{"kura.workspace.inspect" => "inspect"})
    skills(["jido"])
    memories(["The demo input is /brief.txt. Report missing or empty input."])
    playbooks(%{"inspect" => ["read_brief", "check_brief"]})
  end

  vsm do
    operation(:delivery)
    operation(:readiness)
    adapter(Kura.Cell.Control.Adapter)
  end
end
