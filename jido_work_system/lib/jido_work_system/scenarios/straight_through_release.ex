defmodule JidoWorkSystem.Scenarios.StraightThroughRelease do
  alias JidoWorkSystem.Scenarios.Scenario

  @beats [
    :define_task,
    :delegate_task,
    :accept_delegation,
    :plan_work,
    :check_authority,
    :select_draft,
    :write_draft,
    :record_complete_evidence,
    :verify_pass,
    :accept_outcome
  ]

  def definition do
    %Scenario{
      key: "straight-through-release",
      title: "The note is ready",
      summary:
        "Mike needs a short note about a new app release. The work cell writes all three parts.",
      learning_point: "The checker checks the note. Then Mike says the job is done.",
      audience: :interactive,
      steps: @beats
    }
  end
end
