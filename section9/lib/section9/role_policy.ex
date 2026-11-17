defmodule Section9.RolePolicy do
  @moduledoc "Central role permissions for model proposals and committed effects."

  @permissions %{
    lead: ~w(assign_implementer close_mission wait),
    implementer: ~w(submit_candidate wait),
    evaluator: ~w(evaluate_candidate request_rework wait)
  }

  def roles, do: [:lead, :implementer, :evaluator]
  def allowed?(role, action), do: action in Map.fetch!(@permissions, role)
  def actions(role), do: Map.fetch!(@permissions, role)

  def writable_paths(:implementer), do: ["fixture/workspace/lib/job_server.ex"]
  def writable_paths(_role), do: []
end
