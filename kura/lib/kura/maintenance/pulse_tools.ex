defmodule Kura.Maintenance.PulseTools do
  @moduledoc false

  @behaviour Jido.AI.ToolSource

  @impl true
  def list_tools(:select, _context) do
    {:ok,
     [
       %{
         name: "use_playbook",
         description: "Start the applicable approved HTN playbook for this CI failure.",
         parameter_schema: []
       }
     ]}
  end

  @impl true
  def run_tool(%{name: "use_playbook", arguments: args}, :select, _context)
      when map_size(args) == 0,
      do: {:ok, %{"intent" => "start_playbook"}}

  def run_tool(_, _, _), do: {:error, :invalid_playbook_request}
end
