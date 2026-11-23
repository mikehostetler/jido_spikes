defmodule Kura.Cell.Host do
  @moduledoc false

  def options do
    [
      registry: Kura.Cell.Registry,
      supervisor: Kura.Cell.Supervisor,
      bus_prefix: "kura:",
      signal_namespace: "kura.cell",
      store: Kura.Cell.Store,
      open_workspace: &Kura.Cell.Workspace.open/1,
      notify: &notify_dashboard/1
    ]
  end

  defp notify_dashboard(entry) do
    Phoenix.PubSub.broadcast(Kura.PubSub, "cell:" <> entry.cell_id, :cell_changed)
  end
end
