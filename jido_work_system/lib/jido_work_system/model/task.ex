defmodule JidoWorkSystem.Model.Task do
  use JidoWorkSystem.Model.Base, table: "tasks"

  attributes do
    attribute(:title, :string, allow_nil?: false, public?: true)
    attribute(:purpose, :string, allow_nil?: false, public?: true)
    attribute(:required_output, :string, allow_nil?: false, public?: true)
    attribute(:quantity, :string, allow_nil?: false, public?: true)
    attribute(:quality, :string, allow_nil?: false, public?: true)
    attribute(:target_completion_time, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:resource_limits, :string, allow_nil?: false, public?: true)
    attribute(:discretion_limits, :string, allow_nil?: false, public?: true)
    attribute(:escalation_conditions, :string, allow_nil?: false, public?: true)
    attribute(:status, :string, allow_nil?: false, default: "defined", public?: true)
  end

  relationships do
    belongs_to(:work_system, JidoWorkSystem.Model.WorkSystem,
      allow_nil?: false,
      attribute_public?: true
    )

    belongs_to(:accountable_actor, JidoWorkSystem.Model.HumanActor,
      allow_nil?: false,
      attribute_public?: true
    )

    has_many(:delegations, JidoWorkSystem.Model.Delegation)
    has_many(:judgments, JidoWorkSystem.Model.Judgment)
    has_many(:mutations, JidoWorkSystem.Model.Mutation)
    has_many(:evidence, JidoWorkSystem.Model.Evidence)
  end
end
