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

  def list_tools(:learn, _context) do
    {:ok,
     [
       %{
         name: "propose_playbook_edit",
         description: "Propose an evidence-based change to one HTN method for operator review.",
         parameter_schema: [
           method: [type: :string, required: true, doc: "Method name from the current playbook"],
           condition: [
             type: :string,
             required: true,
             doc: "Named applicability condition from the available catalog"
           ]
         ]
       }
     ]}
  end

  @impl true
  def run_tool(%{name: "use_playbook", arguments: args}, :select, _context)
      when map_size(args) == 0,
      do: {:ok, %{"intent" => "start_playbook"}}

  def run_tool(%{name: "propose_playbook_edit", arguments: args}, :learn, _context) do
    case args do
      %{method: method, condition: condition} when map_size(args) == 2 ->
        {:ok, %{"method" => method, "condition" => condition}}

      %{"method" => method, "condition" => condition} when map_size(args) == 2 ->
        {:ok, %{"method" => method, "condition" => condition}}

      _ ->
        {:error, :invalid_playbook_edit}
    end
  end

  def run_tool(_, _, _), do: {:error, :invalid_playbook_request}
end
