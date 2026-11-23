defmodule Kura.Maintenance.Pulse do
  @moduledoc "Cedar's prompt and tool policy for maintenance events."
  @behaviour Jido.Holon.Pulse

  alias Kura.Cell.Cognition
  alias Kura.Maintenance
  alias Kura.Maintenance.{Learning, PulseTools}

  @impl true
  def run(_cell, _workspace, %{kind: "case_closed", scope_id: case_id}) do
    case Maintenance.fetch(case_id) do
      %{id: ^case_id} = record -> Learning.run(record)
      _ -> {{:error, :case_unavailable}, nil}
    end
  end

  def run(cell, _workspace, entry) do
    case Maintenance.fetch(entry.scope_id) do
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
        cell = if state["pool_id"], do: %{cell | cognition: "local"}, else: cell

        trace =
          Cognition.pulse(
            cell,
            "Cedar's wake-up event and evidence:\n" <> JSON.encode!(evidence),
            """
            You are processing a maintenance case for Cedar. Respond to the wake-up event.
            For ci_snapshot, assess the check against the tracked head. Use use_playbook when
            the approved CI triage playbook is available and its task fits the failure.
            The tool records intent only.
            For review_reply, assess what the finding adds and say what is still needed.
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

  defp tools(:select) do
    {%{jido_ai_tool_sources: [{PulseTools, :select}]},
     %{requirement: :optional, visible: ["use_playbook"]}}
  end

  defp tools(_purpose), do: {%{}, %{requirement: :disabled}}
end
