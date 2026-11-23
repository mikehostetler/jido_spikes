defmodule Kura.Cells.Pine do
  require Kura.Cell.Control.Adapter
  use Jido.Holon, vsm: true, name: "pine", description: "Workspace inspector"

  alias Kura.Playbooks.Observation

  def pulse_handlers do
    Map.put(Kura.Cells.Inspector.pulse_handlers(), "workspace_observation", Observation)
  end

  def playbook_tasks, do: %{"record_observation" => Observation.registration()}

  holon do
    role("inspector/ROLE.md")
    capabilities(["workspace_read", "digest"])

    signals(%{
      "kura.workspace.inspect" => "inspect",
      "kura.workspace.observed" => "workspace_observation"
    })

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
