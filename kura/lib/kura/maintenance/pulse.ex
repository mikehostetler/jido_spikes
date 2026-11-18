defmodule Kura.Maintenance.Pulse do
  @moduledoc "Cedar's prompt and tool policy for maintenance events."
  @behaviour Kura.Cell.Pulse

  alias Kura.Cell.Cognition
  alias Kura.Maintenance
  alias Kura.Maintenance.PulseTools

  @impl true
  def run(cell, _workspace, entry) do
    case Maintenance.current() do
      %{id: id, state: state} when id == entry.scope_id ->
        [failure | _] = events = state["events"]
        review = Enum.find(events, &(&1["actor"] == "Review"))

        evidence = %{
          "trigger" => entry.kind,
          "event" => Map.delete(entry.payload, "receipt"),
          "original_failure" => failure["evidence"],
          "current_head" => state["current_head"],
          "playbook_used" =>
            state["playbook"] && Map.take(state["playbook"], ["version", "result"]),
          "review_finding" => review && review["message"],
          "case_status_from_code" => state["phase"]
        }

        {context, policy} = tools(purpose(state, entry.kind, entry.payload))

        trace =
          Cognition.pulse(
            cell,
            "Cedar's wake-up event and evidence:\n" <> JSON.encode!(evidence),
            """
            You are Cedar, the maintenance steward. Respond to the wake-up event.
            For ci_snapshot, assess the check against the tracked head. Use use_playbook when
            the approved CI triage playbook is available and its task fits the failure.
            The tool records intent only.
            For review_reply, assess what the finding adds and say what is still needed.
            For case_closed, decide whether the case supports a change to the playbook.
            Compare the method actually selected, the CI evidence, and Review's finding.
            If ask_review used a child turn to repeat facts Cedar already had, consider
            narrowing that method while keeping Review available for incomplete reports.
            The named condition missing_assertion is true when CI omits expected or observed
            results. Call propose_playbook_edit if you recommend the change. An operator
            will compare both versions on detailed and incomplete fixture cases.
            Use one or two short sentences. The supplied case status comes from code.
            Do not claim a passing check on the current head without evidence.
            """,
            context,
            policy
          )

        result =
          case trace do
            %{"status" => "local_demo"} ->
              {:ok, "Assessed local fixture"}

            %{"status" => "completed", "output" => output} ->
              {:ok, output || "Assessment complete"}

            _ ->
              {:error, trace["reason"] || :cognition_incomplete}
          end

        {result, trace}

      _ ->
        {{:error, :case_unavailable}, nil}
    end
  end

  @impl true
  def commit(entry, result, trace), do: Maintenance.commit_pulse(entry, result, trace)

  def purpose(%{"triage_version" => id}, "ci_snapshot", %{"id" => "failure"})
      when is_binary(id),
      do: :select

  def purpose(%{"triage_version" => id}, "case_closed", _payload) when is_binary(id), do: :learn
  def purpose(_state, _kind, _payload), do: nil

  defp tools(purpose) when purpose in [:select, :learn] do
    tool = if purpose == :select, do: "use_playbook", else: "propose_playbook_edit"

    {%{jido_ai_tool_sources: [{PulseTools, purpose}]}, %{requirement: :optional, visible: [tool]}}
  end

  defp tools(_purpose), do: {%{}, %{requirement: :disabled}}
end
