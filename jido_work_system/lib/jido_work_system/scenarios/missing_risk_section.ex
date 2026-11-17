defmodule JidoWorkSystem.Scenarios.MissingRiskSection do
  alias JidoWorkSystem.Scenarios.Scenario

  @steps [
    :define_task,
    :delegate_task,
    :accept_delegation,
    :plan_work,
    :check_authority,
    :select_draft,
    :write_draft,
    :record_incomplete_evidence,
    :verify_fail,
    {:choice,
     %{
       "request_revision" => {:request_revision, :running},
       "end_run" => {:end_run, :ended}
     }},
    :rework_judgment,
    :revise_draft,
    :record_revised_evidence,
    :verify_revised,
    :accept_after_rework
  ]

  def definition do
    %Scenario{
      key: "missing-risk-section",
      title: "The note is missing a part",
      summary:
        "Mike needs a short note about a new app release. The work cell forgets to say what could go wrong.",
      learning_point: "The checker finds the missing part. Mike asks the work cell to fix it.",
      audience: :interactive,
      steps: @steps
    }
  end
end
