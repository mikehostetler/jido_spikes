defmodule JidoWorkSystem.SceneProjection do
  @moduledoc """
  Builds the JSON-safe visual projection for one scenario run.
  """

  alias JidoWorkSystem.Scenarios

  @schema_version 1

  def build(snapshot) do
    run = snapshot.run
    {:ok, scenario} = Scenarios.fetch(run.scenario_key)
    event = List.last(snapshot.events)
    task = List.first(snapshot.tasks)
    evaluation = List.last(snapshot.evaluations)
    outcome = List.last(snapshot.outcomes)

    %{
      schema_version: @schema_version,
      run_id: run.id,
      scenario: %{
        key: scenario.key,
        title: scenario.title,
        summary: scenario.summary,
        learning_point: scenario.learning_point
      },
      revision: run.revision,
      cursor: run.cursor,
      status: run.status,
      current_beat: run.current_beat,
      narration: narration(event, scenario.summary),
      controls: controls(run),
      scene: %{
        locations: locations(),
        actors: actors(run),
        task: task_projection(task, run),
        evidence: evidence_projection(snapshot.evidence),
        verifier: verifier_projection(evaluation),
        outcome: outcome_projection(outcome)
      },
      transition: transition(run.current_beat, snapshot)
    }
  end

  defp controls(run) do
    active? = run.status in ["ready", "running"]

    %{
      can_step: active?,
      can_play: active?,
      choices: choices(run)
    }
  end

  defp choices(%{status: "waiting_for_choice"}) do
    [
      %{id: "request_revision", label: "Ask the cell to fix it"},
      %{id: "end_run", label: "Stop the job"}
    ]
  end

  defp choices(_run), do: []

  defp locations do
    [
      %{id: "owner-desk", label: "Mike's desk"},
      %{id: "handoff", label: "Give the job"},
      %{id: "workbench", label: "Writing work cell"},
      %{id: "verification-desk", label: "Checker"}
    ]
  end

  defp actors(run) do
    [
      %{
        id: "mike",
        label: "Mike",
        kind: "human",
        location: human_location(run.current_beat)
      },
      %{
        id: "release-note-cell",
        label: "Writing work cell",
        kind: "work_cell",
        location: cell_location(run.cursor)
      }
    ]
  end

  defp human_location(beat)
       when beat in [
              "delegate_task",
              "request_revision",
              "accept_outcome",
              "accept_after_rework",
              "end_run"
            ],
       do: "handoff"

  defp human_location(_beat), do: "owner-desk"

  defp cell_location(cursor) when cursor < 2, do: "workbench"
  defp cell_location(2), do: "handoff"
  defp cell_location(_cursor), do: "workbench"

  defp task_projection(nil, _run), do: nil

  defp task_projection(task, run) do
    %{
      id: task.id,
      title: task.title,
      status: task.status,
      holder: task_holder(run),
      location: task_location(run)
    }
  end

  defp task_holder(%{current_beat: "define_task"}), do: "mike"
  defp task_holder(%{status: status}) when status in ["complete", "ended"], do: "mike"
  defp task_holder(_run), do: "release-note-cell"

  defp task_location(%{current_beat: "define_task"}), do: "owner-desk"
  defp task_location(%{current_beat: "delegate_task"}), do: "handoff"

  defp task_location(%{current_beat: beat})
       when beat in [
              "record_complete_evidence",
              "record_incomplete_evidence",
              "record_revised_evidence",
              "verify_pass",
              "verify_fail",
              "verify_revised"
            ],
       do: "verification-desk"

  defp task_location(%{status: status}) when status in ["complete", "ended"], do: "handoff"
  defp task_location(_run), do: "workbench"

  defp evidence_projection(evidence) do
    Enum.map(evidence, fn item ->
      %{
        id: item.id,
        label: "Checked note #{String.slice(item.id, 0, 4)}",
        location: "verification-desk",
        independently_checkable: item.independently_checkable
      }
    end)
  end

  defp verifier_projection(nil), do: %{status: "idle", verdict: nil}

  defp verifier_projection(evaluation) do
    %{status: evaluation.verification_status, verdict: evaluation.verdict}
  end

  defp outcome_projection(nil), do: nil

  defp outcome_projection(outcome) do
    %{
      status: outcome.status,
      human_acceptance: outcome.human_acceptance,
      summary: outcome.summary
    }
  end

  defp narration(nil, fallback), do: fallback
  defp narration(event, _fallback), do: event.summary

  defp transition("ready", _snapshot), do: nil

  defp transition(beat, snapshot) do
    latest_evidence = List.last(snapshot.evidence)

    case beat do
      "define_task" ->
        cue("appear", "task", nil, "owner-desk", 450)

      "delegate_task" ->
        cue("handoff", "mike", "owner-desk", "handoff", 850)

      "accept_delegation" ->
        cue("move", "release-note-cell", "handoff", "workbench", 750)

      "plan_work" ->
        cue("focus", "release-note-cell", "workbench", "workbench", 500)

      "check_authority" ->
        cue("authority", "release-note-cell", "workbench", "workbench", 500)

      "select_draft" ->
        cue("focus", "release-note-cell", "workbench", "workbench", 500)

      "write_draft" ->
        cue("work", "task", "handoff", "workbench", 700)

      "record_complete_evidence" ->
        evidence_cue(latest_evidence)

      "record_incomplete_evidence" ->
        evidence_cue(latest_evidence)

      "verify_pass" ->
        cue("verify_pass", "verifier", "verification-desk", "verification-desk", 650)

      "verify_fail" ->
        cue("verify_fail", "verifier", "verification-desk", "verification-desk", 650)

      "request_revision" ->
        cue("handoff", "mike", "owner-desk", "handoff", 850)

      "rework_judgment" ->
        cue("focus", "release-note-cell", "workbench", "workbench", 500)

      "revise_draft" ->
        cue("work", "task", "verification-desk", "workbench", 700)

      "record_revised_evidence" ->
        evidence_cue(latest_evidence)

      "verify_revised" ->
        cue("verify_pass", "verifier", "verification-desk", "verification-desk", 650)

      "accept_outcome" ->
        cue("accept", "mike", "owner-desk", "handoff", 850)

      "accept_after_rework" ->
        cue("accept", "mike", "owner-desk", "handoff", 850)

      "end_run" ->
        cue("reject", "mike", "owner-desk", "handoff", 650)

      _beat ->
        nil
    end
  end

  defp evidence_cue(nil), do: nil

  defp evidence_cue(evidence) do
    cue("deliver_evidence", evidence.id, "workbench", "verification-desk", 900)
  end

  defp cue(kind, subject_id, from, to, duration_ms) do
    %{kind: kind, subject_id: subject_id, from: from, to: to, duration_ms: duration_ms}
  end
end
