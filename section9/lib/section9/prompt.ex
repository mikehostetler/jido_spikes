defmodule Section9.Prompt do
  @moduledoc "Central role prompts and bounded context rendering."

  @max_chars 20_000

  @roles %{
    lead: """
    You are the lead. Assign pending or rework work to the implementer. Track
    committed progress. Close the mission only when the current candidate has
    a passing independent evaluation. Do not write source or waive tests.
    """,
    implementer: """
    You are the implementer. Repair only the supplied JobServer source. Submit
    a complete replacement source artifact. You cannot see or change protected
    test code. Preserve the module name and public API.
    """,
    evaluator: """
    You are the evaluator. Request an independent acceptance run for the current
    candidate. You cannot edit the candidate, silently repair it, or waive a
    failed check. A failed run requires rework.
    """
  }

  def render(role, context) do
    state = context.actor.state
    task = context.task

    input =
      """
      # Section 9 cognitive pulse

      $jido complete one role-scoped step for this repair mission.

      Before any other model action, call load_skill with name "jido". Then call
      load_skill_resource for "references/commands.md". Follow the loaded Jido
      route within this role's authority. The host will reject this pulse if
      either required skill load is absent.

      Load only the minimum extra Jido resources required for this role step.
      Return the final JSON proposal within eight model calls.

      ## Stable identity
      Role: #{role}
      Mission: Repair one Elixir GenServer cancellation and late-result bug.

      ## Role policy
      #{String.trim(Map.fetch!(@roles, role))}

      Allowed actions: #{Enum.join(Section9.RolePolicy.actions(role), ", ")}
      Writable paths: #{inspect(Section9.RolePolicy.writable_paths(role))}

      Host skill record: #{Jason.encode!(context.actor.skills, pretty: true)}

      ## Committed actor state
      #{Jason.encode!(state, pretty: true)}

      ## Shared ledger facts
      Mission status: #{context.mission.status}
      Pulse budget: #{context.mission.pulses_used}/#{context.mission.pulse_budget}
      Task status: #{task.status}
      Owner: #{task.owner || "none"}
      Claim generation: #{task.claim_generation}
      Candidate: #{candidate_summary(context.candidate)}
      Evaluation: #{evaluation_summary(context.evaluation)}

      ## Acceptance contract
      #{context.acceptance_contract}

      ## Starting source
      ```elixir
      #{context.broken_source}
      ```

      ## Recent committed events
      #{Jason.encode!(context.recent_events, pretty: true)}

      Return one structured proposal. Replace the complete actor state. State
      facts must name evidence, not hidden reasoning. Do not claim that a test
      passed before the evaluator records command evidence.

      Return only JSON that matches this proposal schema after all required
      skill tool calls are complete:
      #{Jason.encode!(Section9.Proposal.schema(role), pretty: true)}
      """
      |> String.trim()

    if String.length(input) > @max_chars, do: raise("Section 9 model input is too large")

    %{
      system:
        "Run one bounded ReAct cognitive cycle. Use only committed facts and the role policy.",
      user: input,
      exact:
        "[SYSTEM]\nRun one bounded ReAct cognitive cycle. Use only committed facts and the role policy.\n\n[USER]\n#{input}",
      schema: Section9.Proposal.schema(role)
    }
  end

  defp candidate_summary(nil), do: "none"

  defp candidate_summary(candidate),
    do: "#{candidate.id} (generation #{candidate.claim_generation}, #{candidate.status})"

  defp evaluation_summary(nil), do: "none"
  defp evaluation_summary(evaluation), do: "#{evaluation.id} passed=#{evaluation.passed}"
end
