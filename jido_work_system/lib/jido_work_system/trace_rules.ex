defmodule JidoWorkSystem.TraceRules do
  @moduledoc """
  Checks the general rules that every saved work trace must follow.

  A rule returns a small, JSON-safe problem map. An empty list means that the
  trace state follows all current rules.
  """

  alias JidoWorkSystem.Simulation

  def check(snapshot) do
    [
      &run_matches_trace/1,
      &events_are_ordered/1,
      &task_has_an_owner/1,
      &delegation_is_valid/1,
      &work_was_accepted/1,
      &decisions_explain_judgments/1,
      &changes_follow_rules/1,
      &checks_use_saved_work/1,
      &outcome_follows_a_check/1,
      &terminal_state_is_closed/1
    ]
    |> Enum.flat_map(& &1.(snapshot))
  end

  defp run_matches_trace(snapshot) do
    run = snapshot.run
    event_count = length(snapshot.events)

    []
    |> add_unless(run.cursor == run.revision, "run_position", "Step and change numbers differ.")
    |> add_unless(
      run.revision == event_count,
      "event_count",
      "The change number does not match the number of saved steps."
    )
  end

  defp events_are_ordered(snapshot) do
    actual = Enum.map(snapshot.events, & &1.sequence)
    expected = if actual == [], do: [], else: Enum.to_list(1..length(actual))

    add_unless([], actual == expected, "event_order", "Saved steps are missing or out of order.")
  end

  defp task_has_an_owner(%{tasks: []}), do: []

  defp task_has_an_owner(snapshot) do
    human_ids = ids(snapshot.humans)

    Enum.flat_map(snapshot.tasks, fn task ->
      []
      |> add_unless(
        task.work_system_id == snapshot.system.id,
        "task_system",
        "The job belongs to another work system."
      )
      |> add_unless(
        MapSet.member?(human_ids, task.accountable_actor_id),
        "task_owner",
        "The job has no valid person who owns it."
      )
      |> add_unless(
        complete_job?(task),
        "job_contract",
        "The job does not say why it exists, what to make, or what good means."
      )
    end)
  end

  defp delegation_is_valid(snapshot) do
    task_ids = ids(snapshot.tasks)
    human_ids = ids(snapshot.humans)
    cell_ids = ids(snapshot.cells)
    authority_ids = ids(snapshot.authorities)

    Enum.flat_map(snapshot.delegations, fn delegation ->
      []
      |> add_unless(
        MapSet.member?(task_ids, delegation.task_id),
        "delegation_job",
        "A handoff has no valid job."
      )
      |> add_unless(
        MapSet.member?(human_ids, delegation.from_actor_id),
        "delegation_owner",
        "A handoff has no valid person."
      )
      |> add_unless(
        MapSet.member?(cell_ids, delegation.to_cell_id),
        "delegation_cell",
        "A handoff has no valid work cell."
      )
      |> add_unless(
        MapSet.member?(authority_ids, delegation.authority_id),
        "delegation_rules",
        "A handoff has no valid job rules."
      )
    end)
  end

  defp work_was_accepted(snapshot) do
    accepted_task_ids =
      snapshot.delegations
      |> Enum.filter(&(&1.status == "accepted"))
      |> Enum.map(& &1.task_id)
      |> MapSet.new()

    cell_ids = ids(snapshot.cells)

    Enum.flat_map(snapshot.work, fn work ->
      []
      |> add_unless(
        MapSet.member?(accepted_task_ids, work.task_id),
        "work_acceptance",
        "Work started before a work cell accepted the job."
      )
      |> add_unless(
        MapSet.member?(cell_ids, work.work_cell_id),
        "work_cell",
        "Saved work has no valid work cell."
      )
    end)
  end

  defp decisions_explain_judgments(snapshot) do
    judgment_ids = ids(snapshot.judgments)
    decision_judgment_ids = MapSet.new(snapshot.decisions, & &1.judgment_id)

    []
    |> add_unless(
      MapSet.subset?(judgment_ids, decision_judgment_ids),
      "judgment_decision",
      "A work-cell choice has no saved decision."
    )
  end

  defp changes_follow_rules(snapshot) do
    authorities = Map.new(snapshot.authorities, &{&1.id, &1})
    work_ids = ids(snapshot.work)
    workspace = List.first(snapshot.workspaces)

    Enum.flat_map(snapshot.mutations, fn mutation ->
      authority = Map.get(authorities, mutation.authority_id)
      path = mutation.resulting_state["path"]

      []
      |> add_unless(mutation.authorized, "change_permission", "A saved change was not allowed.")
      |> add_unless(
        authority && Simulation.authorized?(authority, mutation.action),
        "change_action",
        "A saved change used an action that the job rules do not allow."
      )
      |> add_unless(
        MapSet.member?(work_ids, mutation.work_execution_id),
        "change_work",
        "A saved change has no matching work record."
      )
      |> add_unless(
        workspace && path && Simulation.bounded_path?(workspace, path),
        "change_path",
        "A saved change is outside the safe work area."
      )
      |> add_unless(
        is_binary(mutation.receipt) && byte_size(mutation.receipt) > 0,
        "change_receipt",
        "A saved change has no receipt."
      )
    end)
  end

  defp checks_use_saved_work(snapshot) do
    mutation_ids = ids(snapshot.mutations)
    evidence_ids = ids(snapshot.evidence)

    evidence_problems =
      Enum.flat_map(snapshot.evidence, fn evidence ->
        []
        |> add_unless(
          MapSet.member?(mutation_ids, evidence.mutation_id),
          "proof_change",
          "A checked result has no saved change."
        )
        |> add_unless(
          evidence.independently_checkable,
          "proof_checkable",
          "The result cannot be checked by another checker."
        )
      end)

    evaluation_problems =
      Enum.flat_map(snapshot.evaluations, fn evaluation ->
        add_unless(
          [],
          MapSet.member?(evidence_ids, evaluation.evidence_id),
          "check_proof",
          "A check has no saved result to check."
        )
      end)

    evidence_problems ++ evaluation_problems
  end

  defp outcome_follows_a_check(snapshot) do
    evaluations = Map.new(snapshot.evaluations, &{&1.id, &1})
    human_ids = ids(snapshot.humans)

    Enum.flat_map(snapshot.outcomes, fn outcome ->
      evaluation = Map.get(evaluations, outcome.evaluation_id)

      []
      |> add_unless(evaluation != nil, "outcome_check", "The final choice has no matching check.")
      |> add_unless(
        outcome.human_acceptance != "accepted" ||
          (evaluation && evaluation.verification_status == "passed"),
        "accepted_failed_work",
        "The person accepted work that did not pass its check."
      )
      |> add_unless(
        MapSet.member?(human_ids, outcome.accepted_by_id),
        "outcome_owner",
        "The final choice has no valid person."
      )
    end)
  end

  defp terminal_state_is_closed(%{run: %{status: status}} = snapshot)
       when status in ["complete", "ended"] do
    task = List.first(snapshot.tasks)

    closing_event? =
      case List.last(snapshot.events) do
        %{kind: kind} -> kind in ["delegation_rejected", "job_canceled", "deadline_missed"]
        nil -> false
      end

    []
    |> add_unless(
      (closing_event? && snapshot.outcomes == []) || length(snapshot.outcomes) == 1,
      "final_outcome",
      "A finished job needs one final choice or one clear closing reason."
    )
    |> add_unless(
      task && task.status in ["accepted", "rejected", "declined", "canceled", "expired"],
      "final_job",
      "A finished job is still open."
    )
    |> add_unless(
      snapshot.work == [] || Enum.all?(snapshot.work, &(&1.status == "complete")),
      "final_work",
      "A finished job still has open work."
    )
  end

  defp terminal_state_is_closed(%{run: %{status: "waiting_for_choice"}} = snapshot) do
    evaluation = List.last(snapshot.evaluations)

    add_unless(
      [],
      evaluation && evaluation.verification_status == "failed",
      "choice_reason",
      "The system asked the person to choose, but no failed check explains why."
    )
  end

  defp terminal_state_is_closed(_snapshot), do: []

  defp complete_job?(task) do
    Enum.all?([task.purpose, task.required_output, task.quality], &present?/1)
  end

  defp present?(value), do: is_binary(value) && String.trim(value) != ""
  defp ids(items), do: MapSet.new(items, & &1.id)

  defp add_unless(problems, true, _code, _message), do: problems

  defp add_unless(problems, false, code, message) do
    problems ++ [%{code: code, message: message}]
  end
end
