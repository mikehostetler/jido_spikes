defmodule JidoWorkSystem.Scenarios.HeadlessCatalog do
  @moduledoc false

  alias JidoWorkSystem.Scenarios.Scenario

  @success_tail [
    :check_authority,
    :select_draft,
    :write_draft,
    :record_complete_evidence,
    :verify_pass,
    :accept_outcome
  ]

  @accepted_start [:define_task, :delegate_task, :accept_delegation, :plan_work]

  def list do
    [
      story(
        "clarify-before-work",
        "Mike explains an unclear job",
        "The work cell asks a question before it accepts the job.",
        "A work cell should ask before it guesses.",
        [:request_clarification, :clarification_received] ++ @accepted_start ++ @success_tail
      ),
      story(
        "cell-declines-job",
        "The work cell says no",
        "The work cell cannot do the job with its current tools.",
        "A handoff is an offer. A work cell can say no.",
        [:define_task, :delegate_task, {:beat, :reject_delegation, :ended}]
      ),
      story(
        "missing-facts-recovered",
        "Mike supplies a missing fact",
        "The work cell stops until Mike supplies a fact that it needs.",
        "Missing facts should stop work before they cause a bad result.",
        @accepted_start ++ [:facts_missing, :provide_facts] ++ @success_tail
      ),
      story(
        "extra-permission-granted",
        "Mike grants one more permission",
        "The work cell asks before it uses an action outside the first job rules.",
        "The owner can add a small permission without replacing the job.",
        @accepted_start ++ [:permission_denied, :grant_permission] ++ @success_tail
      ),
      story(
        "tool-failure-retry",
        "The note writer fails once",
        "The work cell records a tool failure and safely tries again.",
        "A retry must be visible and must still follow the job rules.",
        @accepted_start ++
          [:check_authority, :select_draft, :tool_failed, :retry_tool, :write_draft] ++
          [:record_complete_evidence, :verify_pass, :accept_outcome]
      ),
      story(
        "checker-delay",
        "The checker is late",
        "The finished note waits until the checker is ready.",
        "Waiting is a real work state. It must not look like completed work.",
        @accepted_start ++
          [:check_authority, :select_draft, :write_draft, :record_complete_evidence] ++
          [:checker_unavailable, :checker_returns, :verify_pass, :accept_outcome]
      ),
      story(
        "owner-cancels-work",
        "Mike cancels the job",
        "Mike stops a job after the work cell starts it.",
        "The owner can stop work, and the open work must close.",
        @accepted_start ++ [{:beat, :cancel_job, :ended}]
      ),
      story(
        "deadline-stop",
        "The job misses its deadline",
        "The work cell stops when the deadline passes.",
        "A missed deadline must close or change the job.",
        @accepted_start ++ [{:beat, :deadline_missed, :ended}]
      ),
      story(
        "late-change-request",
        "Mike changes the job",
        "Mike adds one clear need after the first draft.",
        "A changed job must save the new finish line before work continues.",
        @accepted_start ++
          [:check_authority, :select_draft, :write_draft, :change_job, :revise_draft] ++
          [:record_revised_evidence, :verify_revised, :accept_after_rework]
      ),
      story(
        "nested-specialist-cell",
        "A smaller cell helps",
        "The writing work cell asks a smaller specialist cell for help.",
        "A smaller work cell must leave its own work record.",
        @accepted_start ++
          [:delegate_to_specialist, :specialist_returns] ++ @success_tail
      ),
      story(
        "second-check-fails",
        "The repair still fails",
        "The work cell repairs the note, but the second check still finds a missing part.",
        "A repair limit can stop an endless loop.",
        @accepted_start ++
          [
            :check_authority,
            :select_draft,
            :write_draft,
            :record_incomplete_evidence,
            :verify_fail
          ] ++
          [
            :request_revision,
            :rework_judgment,
            :revise_draft,
            :record_incomplete_evidence,
            :verify_fail,
            {:beat, :stop_after_rework, :ended}
          ]
      ),
      story(
        "owner-rejects-passed-work",
        "Mike rejects a correct note",
        "The note passes its check, but it no longer helps Mike.",
        "A passed check does not force the owner to accept the result.",
        @accepted_start ++
          [:check_authority, :select_draft, :write_draft, :record_complete_evidence, :verify_pass] ++
          [{:beat, :reject_passed_work, :ended}]
      )
    ]
  end

  defp story(key, title, summary, learning_point, steps) do
    %Scenario{
      key: key,
      title: title,
      summary: summary,
      learning_point: learning_point,
      steps: steps,
      audience: :headless
    }
  end
end
