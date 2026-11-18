defmodule Kura.Maintenance.ReviewTool do
  @moduledoc false
  @behaviour Jido.AI.ToolSource

  @impl true
  def list_tools(_config, _context) do
    {:ok,
     [
       %{
         name: "request_review",
         description: "Ask Cedar's Review cell to inspect the original failed CI check.",
         parameter_schema: []
       }
     ]}
  end

  @impl true
  def run_tool(%{name: "request_review", arguments: arguments}, _config, _context)
      when map_size(arguments) == 0 do
    {:ok, %{"recipient" => "cedar/review", "status" => "requested"}}
  end

  def run_tool(_call, _config, _context), do: {:error, :invalid_review_request}
end
